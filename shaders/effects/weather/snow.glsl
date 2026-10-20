/*
积雪覆盖：在露天、朝上的方块表面叠一层雪，让雪原群系在下雪时地面变白。
来源：从 `references/Eclipse/shaders/dimensions/composite1.fsh` 的 `applyPuddles`（第 936 到 971 行，
  条件 `#if ShaderSnow > 0`）移植；选项对应 Eclipse `lib/settings.glsl:363` 的 `ShaderSnow` 与
  `:364` 的 `ShaderSnowStrength`，三张贴图是 Eclipse 的 `texture/snowA.png`、`snowN.png`、`snowR.png`。
调用位置：几何阶段片元的底色、法线与表面贴图都解出之后、写画面之前。
  `rendering/terrain.glsl` 与 `rendering/entities.glsl` 各自在算视空间法线之前调用一次。
可复制示例：
  `omniSnowOverlay(albedo, normalTex, specularTex.r, worldPos, worldNormal, worldFlatNormal, blockLight.y);`
调用前提（由绘制主体先声明这些全局量）：
  世界位置与两个世界空间法线由调用方算好传入；露天程度用几何阶段已有的天光 `blockLight.y`；
  下雪状态由 `bind/weather.glsl` 从 `eyeSnowySmooth` 与 `rainStrength` 转成普通结构体字段；
  三张贴图在开启本效果时由 `rendering/pipeline.properties` 绑定到 `texture/snowA.png`、`snowN.png`、`snowR.png`。
关键设计原因与取舍：
  一、一次改写底色、法线与平滑度。Eclipse 的同一段会叠底色（`snowA`）、扰除法线（`snowN`）、改粗糙度（`snowR`）；
    本项目的粗糙度在五号画面里以打包的平滑度形式存在，没有独立的粗糙度变量，所以这里写回的是平滑度，
    并把它反解成目标粗糙度对应的值（本项目 `粗糙度 = (1 - 平滑度)^2`），详见函数里的两步换算。
    法线写回的是切线空间法线，随后由调用方的切线基转到视空间，所以非朝上的面也能摆正。
  二、默认关闭。`OMNI_SNOW_OVERLAY` 不开时，贴图声明、函数与调用点都被条件编译跳过，默认画面与现在完全一致。
  三、只给地形与实体。Eclipse 只在实体、手、水之外的地表调用（`composite1.fsh:1692`），
    本项目按需求在地形与实体调用，手持物与蜘蛛眼不叠雪。
*/
#ifndef OMNI_SNOW_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_SNOW_INCLUDED // 置上标记，后续再次引用直接跳过。
// 下雪与降雨标记由绑定层整理，积雪只判断普通数值。
#include "/bind/weather.glsl"

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
// 雪法线贴图：来源 Eclipse `texture/snowN.png`，给雪面加细碎起伏，让雪不是一块平白。
uniform sampler2D snowTexN;
// 雪粗糙度贴图：来源 Eclipse `texture/snowR.png`，用绿通道给出雪面的粗糙度，雪通常很粗糙。
uniform sampler2D snowTexR;

// --- 积雪覆盖：把雪的底色、法线与粗糙度按露天程度与朝向叠进这个像素 ---
// 参数 `albedo` 是底色；`normal` 是切线空间法线；`smoothness` 是五号画面里的平滑度（粗糙度由它平方得到），
// 三个量都用 `inout` 传回，调用方拿到的是叠过雪之后的值。
// 参数 `worldPos` 是世界坐标；`normalW` 是叠雪前的世界法线，`flatNormalW` 是几何面的世界法线；
// 参数 `skyVisibility` 是天光分量，零到一，越接近一说明这点越露天。
// 为什么用贴图坐标乘零点一：Eclipse 用 `worldPos.xz*0.1` 让雪纹在世界里平铺，不随方块贴图重复。
// 为什么先算 `upnormal`：把法线朝上的程度转成零到一，面越朝上越接近零，侧面接近一。
// 为什么还要乘露天程度：洞穴与屋檐下的面即使朝上也不该积雪，露天的面才盖雪。
// 调用前提：本函数只在片元阶段调用；降雨与下雪标记由绑定层提供。
void omniSnowOverlay(inout vec3 albedo, inout vec3 normal, inout float smoothness, vec3 worldPos, vec3 normalW, vec3 flatNormalW, float skyVisibility){
	// 下雪状态：所在群系下雪且此刻确实在下才积雪。
	// 这对应 Eclipse 的默认模式一“下雪时”（`shaders.properties:790`）。
	float snowAmount = bind_weather().snowy * step(0.01, bind_weather().rain);
	if (snowAmount < 0.01) return; // 没下雪时直接返回，省掉后面的采样与混合。

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

	// 雪法线：贴图三个通道先解成切线空间法线，再按覆盖程度混进表面法线。
	// Eclipse 在合成阶段把这张法线按 `.xzy` 直接当世界法线用，那是因为雪几乎只落在朝上的面；
	// 本项目写的是切线空间法线，随后由调用方的切线基转到视空间，非朝上的面也能摆正。
	vec3 snowN = normalize(2.0 * texture(snowTexN, snowCoords).rgb - 1.0);

	// 雪粗糙度：Eclipse 把贴图绿通道当作粗糙度直接写回；本项目的粗糙度由平滑度平方得到。
	// 为什么用 `1.0 - sqrt`：反解出与目标粗糙度对应的平滑度再混入，`sqrt(覆盖度)` 的权重照 Eclipse。
	float snowR = texture(snowTexR, snowCoords).g;
	float snowSmoothness = 1.0 - sqrt(saturate(snowR));

	// 融化阶段：雪未积满时 Eclipse 再把粗糙度往零点七五倍收，这里同样反解成平滑度混入。
	float melt = smoothstep(0.15, 0.7, snowAmount) * smoothstep(1.0, 0.8, snowAmount) * effectStrength;
	float meltSmoothness = 1.0 - sqrt(saturate(0.75 * snowR));

	albedo = mix(albedo, 2.5 * snowA, textureMult); // 把雪按覆盖程度混到底色，系数照 Eclipse。
	normal = mix(normal, snowN, textureMult); // 把雪法线按覆盖程度混进切线空间法线。
	smoothness = mix(smoothness, snowSmoothness, sqrt(textureMult)); // 把雪粗糙度按覆盖程度混进平滑度。
	smoothness = mix(smoothness, meltSmoothness, melt); // 融化阶段再往更平滑收一点。
}
#endif // 积雪效果开关结束。
#endif // 文件守卫结束。
