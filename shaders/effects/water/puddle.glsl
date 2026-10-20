/*
水洼：把 Eclipse 的水洼尺寸、湿面反射锐度，以及水洼表面的法线、粗糙度与底色改写，集中成一个文件。
来源：选项取 `references/Eclipse/shaders/lib/settings.glsl` 第三百五十九到三百六十行，算法取
  `references/Eclipse/shaders/dimensions/composite1.fsh` 第八百四十七到九百三十四行的 `applyPuddles`。
职责：提供三个纯计算函数和它们用到的选项，不读写中间画面，也不声明加载器输入。
调用位置：
  `OmniPuddleCoverage` 由 `effects/water/water.glsl` 的 `GetRainNormal` 在「仅水洼」模式里调用，覆盖范围跟随 `OMNI_PUDDLE_SIZE`；
  `OmniPuddleRoughness` 由 `effects/ground/material.glsl` 的 `MaterialFromTex` 调用，用那里的湿润度改写湿表面粗糙度；
  `OmniPuddleSurface` 由 `effects/lighting/composite_surface.glsl` 在「仅水洼」模式里调用，用 `OMNI_PUDDLE_SIZE` 决定的水洼覆盖
    把水洼表面的法线拉平、粗糙度改低、底色压暗，让这个尺寸选项真正表现为水洼，而不只是雨点涟漪的范围。
已知差距：雪面粗糙度已在几何阶段写进五号画面的平滑度，但合成阶段读不到单独的 `snowR`，所以这里湿表面粗糙度固定取零点五，未照 Eclipse 的 `0.5*(1+snowR)`；
  `OmniPuddleSurface` 只按世界横纵坐标取水洼噪声，没有照 Eclipse 按面的朝向换轴，竖直墙面的水洼形状会与 Eclipse 略不同；
  法线压平拉向世界上方而不是几何法线，原因见 `OmniPuddleSurface` 的说明。
可复制示例（`halfWet`、`puddleNoise`、`lightmap` 由调用方按现有湿润流程准备）：
  `float puddles = OmniPuddleCoverage(halfWet, puddleNoise);`
  `roughness = OmniPuddleRoughness(roughness, 0.5, wetnessStages);`  合成阶段读不到雪粗糙度贴图 `snowR`，湿表面粗糙度固定取零点五
  `OmniPuddleSurface(worldNormal, albedo, roughness, f0, skyLight, worldPos);`  只有在 `OMNI_PUDDLE_MODE == 2` 时调用
与现有选项的关系：`effects/water/water.glsl` 的 `OMNI_PUDDLE_MODE` 决定雨点涟漪铺满整片湿面还是只出现在低洼处；
  `OmniPuddleSurface` 只在「仅水洼」（模式二）里执行，模式一、三保持原有的雨点涟漪行为。
默认中性：`OMNI_PUDDLE_SIZE` 默认 1.0，是 Eclipse 的参考值；`OMNI_PUDDLE_REFLECTION_SHARPNESS` 默认 0.0，
  按下面的公式令粗糙度不被湿润改写；`OmniPuddleSurface` 只在非默认的模式二里运行，所以默认画面保持现状。
  Eclipse 默认就会做这几步、该锐度选项默认 0.9，都会改画面，这里改用中性默认，说明见 `OmniPuddleSurface`。
*/
#ifndef OMNI_PUDDLE_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_PUDDLE_INCLUDED // 置上标记，后续再次引用直接跳过。
// 水洼覆盖与湿面粗糙度的纯公式放在通用库，这里只传玩家选项。
#include "/gfx/water.glsl"
// 湿润度与相机位置由绑定层整理，水洼公式只接收普通数值。
#include "/bind/camera.glsl"
#include "/bind/weather.glsl"

// @effect {"label":{"zh_cn":"水洼","en_us":"Puddles"}}
// 菜单页留在「水与地面」：水洼属于地表效果，与水面、地面和植物放在同一页。
// @option {"label":{"zh_cn":"尺寸","en_us":"Puddle size"},"description":{"zh_cn":"低洼处积水范围的大小，调大后水洼更大更连片，调小更零散；来源 Eclipse 的 `Puddle_Size`，默认 1.0 与参考一致。","en_us":"Size of the puddles that form in low spots; larger makes them bigger and better connected. From Eclipse `Puddle_Size`; default 1.0 matches the reference."}}
#define OMNI_PUDDLE_SIZE 1.0 // [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5]
// @option {"label":{"zh_cn":"湿面反射锐度","en_us":"Wet reflection sharpness"},"description":{"zh_cn":"湿表面反射的清晰程度，调大后积水表面更接近镜面；默认 0.0 表示不改动当前粗糙度，Eclipse 默认 0.9。","en_us":"How sharp reflections get on wet ground; larger is more mirror-like. Default 0.0 leaves roughness unchanged; Eclipse default is 0.9."}}
#define OMNI_PUDDLE_REFLECTION_SHARPNESS 0.0 // [0.0 0.9 0.925 0.95 0.975 1.0]

// 水洼覆盖：由湿润度与低洼噪声算出零到一的积水覆盖，供调用方决定水洼范围与暗化强度。
// 为什么先减噪声：噪声代表地势起伏，湿润高于噪声处才是真正低洼，减掉噪声就露出水洼边界。
// 为什么用五次方加指数：让阈值附近的过渡更陡、远离阈值处更平，水洼边缘自然又不整片糊死。
float OmniPuddleCoverage(float halfWet, float noise){
	return gfx_puddle_coverage(halfWet, noise, OMNI_PUDDLE_SIZE); // 覆盖公式在通用库，尺寸选项在这里传入。
}

// 湿面反射锐度：把干表面粗糙度往「湿表面粗糙度」混合，湿得越深反射越清晰。
// `OMNI_PUDDLE_REFLECTION_SHARPNESS` 就是混合比例的上限，默认 0.0 时原样返回，不改变画面。
// 数学与 Eclipse 一致：`mix(roughness, wetRoughness, wetnessStages * 锐度)`，此处不做额外夹取，保持等价。
// 调用点：`effects/ground/material.glsl` 的 `MaterialFromTex`（湿润度取那里的 `wet`）与本文件的 `OmniPuddleSurface`（传水洼权重）。
float OmniPuddleRoughness(float roughness, float wetRoughness, float wetnessStages){
	return gfx_puddle_roughness(roughness, wetRoughness, wetnessStages, OMNI_PUDDLE_REFLECTION_SHARPNESS); // 混合公式在通用库，锐度选项在这里传入。
}

// 水洼表面：把 Eclipse `applyPuddles` 的水洼三步——法线压平、粗糙度改写与反照率压暗——接到已解出的表面上，
// 让 `OMNI_PUDDLE_SIZE` 真正改变水洼的法线、反射与颜色，而不只是雨点涟漪的范围。
// 出处：`references/Eclipse/shaders/dimensions/composite1.fsh` 第八百八十九到九百三十四行的水洼段（`PUDDLE_MODE == 2` 分支）。
// 为什么接在合成阶段：法线、粗糙度与底色都在合成阶段由 `MaterialFromTex` 解出，Eclipse 也在解出后的同一处改它们，位置一致才等价。
// 为什么压平拉向世界上方而不是几何法线：合成阶段只读回压平后的表面法线，拿不到单独的几何法线（Eclipse 里的 `flatNormals`）；
//   Eclipse 的权重 `clamp(flatNormals.y,0,1)` 只让朝上的面被压平，此时几何法线就接近世界上方，拉向世界上方是这一情形下的等价近似。
// 参数：`worldNormal`、`albedo` 与 `roughness` 会被改写；`f0` 用来跳过金属面、`skyLight` 是这天光等级；`worldPos` 是相机相对世界位置。
// 全局依赖：湿润度与相机位置由 `bind/` 从加载器输入转换；`noisetex` 是水洼噪声贴图，由绘制主体声明。
void OmniPuddleSurface(inout vec3 worldNormal, inout vec3 albedo, inout float roughness, float f0, float skyLight, vec3 worldPos){
	vec3 absPos = worldPos + bind_camera().position; // 水洼噪声要绝对世界坐标，用相机相对坐标会让水洼跟着相机跑。
	float halfWet = min(bind_weather().wetness, 1.0); // 全局湿润度的低档，与 Eclipse 的 `halfWet` 同义。
	float noise = texture(noisetex, absPos.xz * 0.02).b; // 低洼形状噪声，值越低地势越低；朝上的面就是主要积水面，所以只取横纵坐标。
	float puddles = OmniPuddleCoverage(halfWet, noise); // 积水覆盖，`OMNI_PUDDLE_SIZE` 已含在公式里，越大水洼越大越连片。
	float wetnessStages = puddles * skyLight * smoothstep(0.85, 1.0, skyLight); // 积水权重：只有露天面才算，照 Eclipse 的 `lightmap` 与 `effectStrength`。
	float wetnessDarkening = min(wetnessStages + OMNI_TEXTURE_DEFAULT_POROSITY * clamp(bind_weather().wetness - 2.0, 0.0, 1.0), 1.0); // 压暗权重，整体很湿时按孔隙率再补一点，照 Eclipse。

	worldNormal = normalize(mix(worldNormal, vec3(0.0, 1.0, 0.0), wetnessStages * clamp(worldNormal.y, 0.0, 1.0))); // 水洼处法线拉平：朝上的面权重最大，照 Eclipse 的 `clamp(flatNormals.y,0,1)`。
	roughness = OmniPuddleRoughness(roughness, 0.5, wetnessStages); // 积水处更光滑；`OMNI_PUDDLE_REFLECTION_SHARPNESS` 决定混合比例，默认零不改画面。
	if (f0 < 229.5 / 255.0) // 金属面不压暗，这个门限照 Eclipse。
		albedo = pow(albedo * (1.0 - 0.08 * wetnessDarkening), vec3(1.0 + 0.7 * wetnessDarkening)); // 幂次压暗并略加饱和，让水洼看起来更深更实。
}
#endif // 文件守卫结束。
