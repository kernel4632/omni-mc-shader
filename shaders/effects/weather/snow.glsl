/*
积雪覆盖：在露天、朝上的方块表面叠一层雪，让雪原群系在下雪时地面变白。
来源：从 `references/Eclipse/shaders/dimensions/composite1.fsh` 的 `applyPuddles`（第 936 到 971 行，
  条件 `#if ShaderSnow > 0`）移植；选项对应 Eclipse `lib/settings.glsl:363` 的 `ShaderSnow` 与
  `:364` 的 `ShaderSnowStrength`，雪底色贴图是 Eclipse 的 `texture/snowA.png`。
调用位置：几何阶段片元的底色解出之后、进入光照之前。
  `rendering/terrain.glsl` 与 `rendering/entities.glsl` 各自在写完零号画面之前调用一次。
可复制示例：
  `albedo = omniSnowOverlay(albedo, worldPos, worldNormal, worldFlatNormal, blockLight.y);`
调用前提（由绘制主体先声明这些全局量）：
  世界位置与两个世界空间法线由调用方算好传入；露天程度用几何阶段已有的天光 `blockLight.y`；
  下雪状态读 `eyeSnowySmooth`（在 `common/uniforms.glsl` 声明）与 `rainStrength`（由绘制主体声明）；
  贴图 `snowTexA` 在开启本效果时由 `rendering/pipeline.properties` 绑定到 `texture/snowA.png`。
关键设计原因与取舍：
  一、只叠底色，不改法线与粗糙度。Eclipse 的同一段还会用 `snowN.png` 扰动法线、用 `snowR.png` 改粗糙度，
    但本项目的粗糙度在五号画面里以打包的高光贴图形式存在，几何阶段没有独立的粗糙度变量；为把改动限制在
    “一小步、只动底色”，这里只做底色叠加，法线与粗糙度的雪留待后续单独小步。
  二、默认关闭。`OMNI_SNOW_OVERLAY` 不开时，贴图声明、函数与调用点都被条件编译跳过，默认画面与现在完全一致。
  三、只给地形与实体。Eclipse 只在实体、手、水之外的地表调用（`composite1.fsh:1692`），
    本项目按需求在地形与实体调用，手持物与蜘蛛眼不叠雪。
*/
#ifndef OMNI_SNOW_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_SNOW_INCLUDED // 置上标记，后续再次引用直接跳过。

// @effect {"label":{"zh_cn":"积雪覆盖","en_us":"Snow cover"}}
// @option {"label":{"zh_cn":"积雪覆盖","en_us":"Snow cover"},"description":{"zh_cn":"下雪时给露天朝上的方块表面叠一层雪；默认关闭，关闭时画面与现在完全一致。","en_us":"Overlays snow on up-facing, sky-exposed block surfaces while it snows; off by default so the default look is unchanged."}}
//#define OMNI_SNOW_OVERLAY
// @option {"label":{"zh_cn":"积雪强度","en_us":"Snow strength"},"description":{"zh_cn":"雪的覆盖厚度与亮度，值越大雪越厚越白；默认照 Eclipse。","en_us":"Thickness and brightness of the snow; larger is thicker and whiter; default matches Eclipse."},"slider":true}
#define OMNI_SNOW_OVERLAY_STRENGTH 1.0 // [0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5]

// 加载器输入声明；调用方通常已先引入，这里再引入一次由守卫去重，保证单独引用也能编译。
#include "/common/uniforms.glsl"
// 共用数学：提供 `saturate` 等小工具。
#include "/common/math.glsl"

#ifdef OMNI_SNOW_OVERLAY // 只有开启本效果时才声明贴图与函数，关闭时完全不增加代码。
// 雪底色贴图：来源 Eclipse `texture/snowA.png`，按世界横纵坐标平铺，给出一片带颗粒感的雪白。
uniform sampler2D snowTexA;

// --- 积雪覆盖：把雪底色按露天程度与朝上程度混进这个像素的底色 ---
// 参数 `worldPos` 是世界坐标；`normalW` 是带贴图扰动的世界法线，`flatNormalW` 是几何面的世界法线；
// 参数 `skyVisibility` 是天光分量，零到一，越接近一说明这点越露天。
// 为什么用贴图坐标乘零点一：Eclipse 用 `worldPos.xz*0.1` 让雪纹在世界里平铺，不随方块贴图重复。
// 为什么先算 `upnormal`：把法线朝上的程度转成零到一，面越朝上越接近零，侧面接近一。
// 为什么还要乘露天程度：洞穴与屋檐下的面即使朝上也不该积雪，露天的面才盖雪。
// 调用前提：本函数只在片元阶段调用；调用方需已声明 `rainStrength`。
vec3 omniSnowOverlay(vec3 albedo, vec3 worldPos, vec3 normalW, vec3 flatNormalW, float skyVisibility){
	// 下雪状态：所在群系下雪（`eyeSnowySmooth`）且此刻确实在下（`rainStrength` 大于零）才积雪。
	// 这对应 Eclipse 的默认模式一“下雪时”（`shaders.properties:790`）。
	float snowAmount = eyeSnowySmooth * step(0.01, rainStrength);
	if (snowAmount < 0.01) return albedo; // 没下雪时直接返回，省掉后面的采样与混合。

	float effectStrength = smoothstep(0.85, 1.0, skyVisibility); // 天光接近满值的露天面才积雪。
	float minClamp = 0.72; // 朝上程度的夹紧下限，照 Eclipse；防止正对镜头的斜面被误判成朝上。

	// 朝上程度：把世界法线按自身分量之和归一后取纵向，再夹到下限之上，得到零到一。
	float upnormal = clamp(-(normalW / dot(abs(normalW), vec3(1.0))).y + clamp(normalW.y, minClamp, 1.0), 0.0, 1.0);

	// 覆盖度：朝上（`upnormal` 小）且露天（`effectStrength` 大）时接近一，其余为负，夹到零。
	float snow = clamp(1.0 - 2.0 * upnormal - (1.0 - effectStrength), 0.0, 1.0);

	vec2 snowCoords = worldPos.xz * 0.1; // 雪纹在世界横纵方向的平铺坐标。

	// 雪底色：按强度把贴图各通道做幂次重整，强度越小曲线越陡、雪越薄。
	vec3 snowA = pow(texture(snowTexA, snowCoords).rgb, vec3(2.0 / (OMNI_SNOW_OVERLAY_STRENGTH - 0.1)));

	// 侧面的雪偏冷偏灰，朝上的面保持贴图原本的亮白；权重按几何面法线的朝上程度。
	snowA = mix(snowA, vec3(0.8, 0.75, 0.85), 1.0 - abs(flatNormalW.y));

	// 覆盖门限：雪越少，门限越靠上，只有雪最厚的地方才显出来，边缘因此自然过渡。
	float omSA = 1.0 - snowAmount;
	float textureMult = smoothstep(0.1 + 0.5 * omSA, 0.5 + 0.9 * omSA, length(snowA) * snow * snowAmount);

	return mix(albedo, 2.5 * snowA, textureMult); // 把雪按覆盖程度混到底色，系数照 Eclipse。
}
#endif // 积雪效果开关结束。
#endif // 文件守卫结束。
