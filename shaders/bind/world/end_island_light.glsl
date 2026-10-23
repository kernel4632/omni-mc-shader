/*
末地主岛光源的宿主接线：读取 Minecraft 输入、调用通用库并写出结果。
调用位置：原引用 `effects/world/end_island_light.glsl` 的程序改为引用本文件。
可复制示例：下方函数保留原有效果入口的签名，调用方式不变。
设计原因与取舍：选项留在效果层，算法在通用库，本文件只做宿主数据与算法之间的转换。
*/
#ifndef OMNI_BIND_WORLD_END_ISLAND_LIGHT_INCLUDED
#define OMNI_BIND_WORLD_END_ISLAND_LIGHT_INCLUDED
#include "/effects/world/end_island_light.glsl"
/*
末地主岛光源：把悬在主岛上方的点光源按距离、视野角与主岛阴影相机照亮附近表面并给高光。
来源：光源位置、视野角与开关取 Eclipse `lib/settings.glsl:419-421`；主岛阴影相机取 Eclipse `dimensions/begin.csh:98-113`、
  `world1/shadow.vsh:90-92` 与 `lib/projections.glsl:52-66`，按 `docs/eclipse-parity.md` 合并，默认关闭。
职责：定义主岛光源的全部选项与内部常数，构造主岛阴影相机（视图与透视矩阵），
  提供把世界位置投到该相机的 `EndLightShadowScreenPos`、求遮挡的 `EndIslandShadow` 与叠加光照的 `EndIslandLighting`。
调用位置：
  `effects/world/end.glsl` 引入本文件；`rendering/shadow.glsl` 也引入本文件，末地阴影顶点在开启主岛光源时用这套相机渲染；
  合成零号在末地有几何的像素上、开启 `OMNI_END_ISLAND_LIGHT` 时调用 `EndIslandLighting`。
可复制示例：
  `gl_Position = endLightShadowProjection * endLightShadowModelView * vec4(endLightWorldPos, 1.0);`
  `finalComposite += EndIslandLighting(worldPos, worldNormal, worldDir, gbuffer.albedo, gbuffer.material.roughness, gbuffer.material.f0, gbuffer.material.metalness);`
调用前提：`cameraPosition` 由 `common/uniforms.glsl` 提供；`Blackbody`、`Fd_Burley`、`SpecularGGX` 由 `common/math.glsl` 提供；
  光照与遮挡函数还要求调用方声明 `shadowtex0` 并打开 `OMNI_SHADOW_COMPARE`（合成零号），阴影顶点阶段不编译这两段。
关键设计原因与取舍：
  Eclipse 另建一盏竖直向下的阴影相机（近十五远二百五十六、视野角七十七），在计算着色器里每帧算好矩阵存进 SSBO；
  这里改为在 GLSL 里用常量与 `cameraPosition` 就地构造，省掉计算着色器与附加缓冲——矩阵只依赖相机与光源位置这两个现成输入。
  主岛光源只在末地有意义，矩阵与函数都用 `OMNI_END` 守卫，主世界与下界不编译这段；默认关闭时整段不参与，画面与原来一致。
*/


// 光源位置与阴影相机范围：照 Eclipse `lib/settings.glsl:419` 与 `dimensions/begin.csh:100-101`，内部常数不进菜单。
#define END_LIGHT_POS vec3(0.0, 190.0, 0.0) // 光源在世界原点正上方一百九十格。
const float END_LIGHT_SHADOW_NEAR = 15.0; // 阴影相机近裁剪面，正好在光源下方十五格。
const float END_LIGHT_SHADOW_FAR = 256.0; // 阴影相机远裁剪面，向下覆盖到主岛以下。

#ifdef OMNI_END // 主岛光源只在末地使用，其它维度不编译下面的矩阵与函数。
// --- 主岛阴影相机：光轴竖直向下，原点抬到光源高度，按相机位置每帧平移 ---
// Eclipse 用 `BuildShadowViewMatrix(normalize(END_LIGHT_POS))` 现算一组基：光轴朝下时横轴取世界 Z、
// 纵轴取世界 X、深度轴取世界 Y；这里把结果直接写成常量矩阵，省掉通用构造函数，只留随相机变化的平移项。
vec3 endLightShadowOrigin = cameraPosition - END_LIGHT_POS; // 光源相对相机的世界偏移，作用在相机相对坐标上正好把光源放到原点。
mat4 endLightShadowModelView = mat4(vec4(0.0, 1.0, 0.0, 0.0), // 相机相对世界的 Z 分量进阴影图横轴。
                                    vec4(0.0, 0.0, 1.0, 0.0), // X 分量进阴影图纵轴。
                                    vec4(1.0, 0.0, 0.0, 0.0), // Y 分量进阴影图深度轴，光轴竖直向下。
                                    vec4(endLightShadowOrigin.z, endLightShadowOrigin.x, endLightShadowOrigin.y, 1.0)); // 平移项。
// 透视投影：视野角来自选项，近远取 Eclipse 的十五与二百五十六，写成标准透视矩阵。
float endLightShadowYScale = 1.0 / tan(radians(OMNI_END_LIGHT_FOV) * 0.5); // 视野角换算成投影缩放。
mat4 endLightShadowProjection = mat4(vec4(endLightShadowYScale, 0.0, 0.0, 0.0), // 横轴缩放。
                                     vec4(0.0, endLightShadowYScale, 0.0, 0.0), // 纵轴缩放。
                                     vec4(0.0, 0.0, (END_LIGHT_SHADOW_FAR + END_LIGHT_SHADOW_NEAR) / (END_LIGHT_SHADOW_NEAR - END_LIGHT_SHADOW_FAR), -1.0), // 深度缩放与透视用的 w。
                                     vec4(0.0, 0.0, 2.0 * END_LIGHT_SHADOW_FAR * END_LIGHT_SHADOW_NEAR / (END_LIGHT_SHADOW_NEAR - END_LIGHT_SHADOW_FAR), 1.0)); // 深度平移。

// 把相机相对世界位置投到主岛阴影图：返回零到一的横纵坐标与深度。
// `worldPos` 是相机相对坐标，矩阵里的平移已含相机位置，两者相加正好得到以光源为原点的世界坐标。
vec3 EndLightShadowScreenPos(vec3 worldPos){
	vec4 clip = endLightShadowProjection * endLightShadowModelView * vec4(worldPos, 1.0); // 投到主岛相机裁剪空间，w 就是到光源的深度。
	if (clip.w <= 0.0) return vec3(2.0); // 落在相机后方或透视退化，返回图纸以外的坐标交给调用方当没遮挡。
	return clip.xyz / clip.w * 0.5 + 0.5; // 透视除法后从负一到一转成零到一。
}

#if defined OMNI_SHADOW_COMPARE // 遮挡查询要读 `shadowtex0`，只有声明它的合成零号编译这段。
// --- 主岛遮挡：把表面投到主岛阴影图，比较深度得到可见度 ---
// 图纸以外当作没有被遮挡：主岛相机没覆盖到的地方硬读边界会压出一条黑边。
float EndIslandShadow(vec3 worldPos){
	vec3 shadowPos = EndLightShadowScreenPos(worldPos); // 表面在主岛阴影图里的位置与深度。
	if (any(lessThan(shadowPos.xy, vec2(0.0))) || any(greaterThan(shadowPos.xy, vec2(1.0))) || shadowPos.z > 1.0) return 1.0; // 图外全亮。

	float sampleDepth = textureLod(shadowtex0, shadowPos.xy, 0.0).x; // 阴影图里该点最近的遮挡深度。
	return step(shadowPos.z - 0.0025, sampleDepth); // 表面比遮挡物更近才算可见；偏移减轻表面自身投出的条纹。
}
#endif // OMNI_SHADOW_COMPARE
#endif // OMNI_END

#if defined OMNI_END && defined OMNI_SHADOW_COMPARE // 光照与遮挡只在末地合成零号参与编译。
// --- 末地主岛光源：把 END_LIGHT_POS 当成悬在主岛上方的点光源，按距离与夹角照亮表面并给高光 ---
// 出处：位置 `lib/settings.glsl:419`、视野角 `:420`、开关 `:421`；Eclipse 在 `dimensions/composite.fsh:509` 按
//   像素到光源重算光方向（`normalize(END_LIGHT_POS-(feetPlayerPos+cameraPosition))`），近处表面受光方向各不相同。
//   遮挡来自 Eclipse 的主岛阴影相机（`dimensions/begin.csh:98-113`、`world1/shadow.vsh:90-92`）。
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
	// 距离衰减：主岛附近接近一；平方反比只作粗略补足，精确的远近关系交给主岛阴影相机。
	float falloff = distFade * cone * OMNI_END_LIGHT_BRIGHTNESS / (1.0 + lightDist * lightDist / 36000.0); // 总衰减。
	falloff *= EndIslandShadow(worldPos); // 乘主岛阴影相机算出的遮挡可见度。

	vec3 lightColor = Blackbody(6000.0) * 0.3; // 与末地太阳同色温、同强度尺度（合成里用 `Blackbody(6000)` 与系数零点三）。
	vec3 result = albedo * lightColor * falloff * Fd_Burley(normal, -viewDir, lightDir, roughness); // 漫反射乘底色。

	float highlightGGX = SpecularGGX(normal, -viewDir, lightDir, clamp(roughness, 0.0015, 0.9), f0); // 与阳光同一套 GGX 高光。
	highlightGGX *= saturate(4.0 - roughness * 3.5); // 光滑面高光更强。
	highlightGGX *= 0.07; // 与阳光高光同一强度尺度。
	result += mix(vec3(1.0), albedo, vec3(metalness)) * lightColor * falloff * highlightGGX; // 金属面高光带底色。

	return result; // 交回可直接叠加到线性光照的颜色。
}
#endif // OMNI_END 与 OMNI_SHADOW_COMPARE
#endif // OMNI_BIND_WORLD_END_ISLAND_LIGHT_INCLUDED
