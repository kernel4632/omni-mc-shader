/*
效果文件 `effects/shared/surface.glsl`：材质解码、G 缓冲读回、材质掩码与水洼表面的唯一实现。
调用位置：地表几何阶段解码资源包材质；合成阶段读回表面并应用水、玻璃、冰与水洼；反射、水面、末地与下界都经它拿同一份表面数据。
可复制示例：
    `Material material = MaterialFromTex(albedo, specTex, wet);`
    `GbufferData data = GetGbufferData();`
    `float puddles = OmniPuddleCoverage(halfWet, puddleNoise);`
设计原因与取舍：材质编号、表面结构、PBR 解码与水洼改写本来就被多个页面共用，拆在“地面”和“水面”两个文件夹里会让
    合成、反射和末地互相引用页面实现。这里把“一个像素的表面是什么”集中成共享主体，选项也随主体只定义一次。
    视差仍然属于地面：它要读方块图集与法线贴图，只有地形、实体与手部需要，因此留在 `effects/ground/parallax.glsl`。
    G 缓冲通道含义仍由 `bind/gbuffer.glsl` 解释，本文件只把选项接进解码，不复制通道编号。
*/
#ifndef OMNI_SHARED_SURFACE_INCLUDED
#define OMNI_SHARED_SURFACE_INCLUDED
// @effect {"label":{"zh_cn":"材质与水洼","en_us":"Materials & puddles"}}

// @option {"label":{"zh_cn":"方块纹理分辨率","en_us":"Block Texture Resolution"},"description":{"zh_cn":"必须等于资源包方块贴图的分辨率，零表示自动。错误的值会让方块视差错位。","en_us":"Must match the resource pack block texture resolution; zero means auto. A wrong value breaks parallax."}}
#define OMNI_TEXTURE_RESOLUTION 0 // [0 1 2 4 8 16 32 64 128 256 512 1024 2048 4096 8192]
// @option {"label":{"zh_cn":"实体纹理分辨率","en_us":"Entity Texture Resolution"},"description":{"zh_cn":"实体视差用的纹理分辨率，必须与资源包一致，否则实体会错位。","en_us":"Texture resolution for entity parallax; must match the pack or entities break."}}
#define OMNI_ENTITIES_TEXTURE_RESOLUTION 16 // [1 2 4 8 16 32 64 128 256 512 1024 2048 4096 8192]
// @option {"label":{"zh_cn":"各向异性过滤","en_us":"Anisotropic Filtering"},"description":{"zh_cn":"让倾斜的表面更清晰；开启视差时会被禁用。","en_us":"Sharper textures on tilted surfaces; disabled while parallax is on."},"values":{"0":{"zh_cn":"关","en_us":"off"},"2":{"zh_cn":"2x","en_us":"2x"},"4":{"zh_cn":"4x","en_us":"4x"},"8":{"zh_cn":"8x","en_us":"8x"},"16":{"zh_cn":"16x","en_us":"16x"}}}
#define OMNI_ANISOTROPIC_FILTERING_QUALITY 4 // [0 2 4 8 16]
// @option {"label":{"zh_cn":"法线高光也过滤","en_us":"Filter Normal & Specular"},"description":{"zh_cn":"把各向异性过滤也用在法线与高光贴图上，代价略高但更清晰。","en_us":"Applies anisotropic filtering to the normal and specular maps too."}}
//#define OMNI_ANISOTROPIC_FILTERING_NORMAL_SPECULAR
// @option {"label":{"zh_cn":"实体凹凸","en_us":"Entity Parallax"},"description":{"zh_cn":"给实体也做视差；需要先正确设置实体纹理分辨率。","en_us":"Enables parallax on entities; set the entity texture resolution first."}}
#define OMNI_ENTITIES_PARALLAX 1 // [0 1]
// @option {"label":{"zh_cn":"凹凸模式","en_us":"Parallax Mode"},"description":{"zh_cn":"关、锐利或平滑；锐利保持像素外观，平滑更少锯齿。","en_us":"Off, Sharp or Smooth; Sharp keeps the pixel look, Smooth has fewer artifacts."},"values":{"0":{"zh_cn":"关","en_us":"off"},"1":{"zh_cn":"锐利","en_us":"Sharp"},"2":{"zh_cn":"平滑","en_us":"Smooth"}}}
#define OMNI_PARALLAX_MODE 0 // [0 1 2]
// @option {"label":{"zh_cn":"凹凸采样质量","en_us":"Parallax Quality"},"description":{"zh_cn":"锐利模式决定视差范围，平滑模式决定伪影多少，越大越细也越慢。","en_us":"Sharp sets the parallax range, Smooth sets artifact level; higher is finer and slower."},"slider":true}
#define OMNI_PARALLAX_QUALITY 40 // [10 15 20 30 40 60 80 100 150 200 300 500]
// @option {"label":{"zh_cn":"凹凸细化步数","en_us":"Parallax Refinements"},"description":{"zh_cn":"平滑视差找到交点后再二分细化的次数，越大边缘越准也越慢。","en_us":"Bisection steps after the parallax hit in Smooth mode; higher is more accurate and slower."},"slider":true}
#define OMNI_PARALLAX_MAX_REFINEMENTS 12 // [0 2 4 6 8 12 16]
// @option {"label":{"zh_cn":"凹凸阴影","en_us":"Parallax Self Shadow"},"description":{"zh_cn":"让视差像素自己也投出阳光阴影，代价很低。","en_us":"Lets parallax pixels cast their own sunlight shadow; cheap."}}
#define OMNI_PARALLAX_SHADOW 1 // [0 1]
// @option {"label":{"zh_cn":"凹凸阴影质量","en_us":"Self Shadow Quality"},"description":{"zh_cn":"视差阴影的采样数，越大越细也越慢。","en_us":"Sample count for the parallax shadow; higher is finer and slower."},"slider":true}
#define OMNI_PARALLAX_SHADOW_QUALITY 20 // [10 15 20 30 40 60 80 100 150 200 300 500]
// @option {"label":{"zh_cn":"由凹凸生成法线","en_us":"Parallax Based Normal"},"description":{"zh_cn":"让法线效果与视差一致；平滑模式只对侧面生效。","en_us":"Keeps normals consistent with parallax; Smooth only affects sides."},"values":{"0":{"zh_cn":"关","en_us":"off"},"1":{"zh_cn":"仅侧面","en_us":"Side Only"},"2":{"zh_cn":"全部","en_us":"All"}}}
#define OMNI_PARALLAX_BASED_NORMAL 1 // [0 1 2]
// @option {"label":{"zh_cn":"凹凸深度","en_us":"Parallax Depth"},"description":{"zh_cn":"凹凸看起来多深，单位是方块高度。","en_us":"How deep surfaces appear, in block heights."},"slider":true}
#define OMNI_PARALLAX_DEPTH 1.0 // [0.1 0.15 0.2 0.3 0.5 0.75 1.0 1.25 1.5 1.75 2.0 3.0 5.0 7.5 10.0]
// @option {"label":{"zh_cn":"凹凸淡出","en_us":"Parallax Fade"},"description":{"zh_cn":"纹理像素很小时淡出视差，避免远处闪烁；不建议关闭。","en_us":"Fades parallax when texels get tiny, avoiding shimmer; better kept on."}}
#define OMNI_PARALLAX_FADE
// @option {"label":{"zh_cn":"启用 PBR","en_us":"Enable PBR"},"description":{"zh_cn":"使用 labPBR 资源包的表面贴图；关闭后下面这些材质效果全部停用。","en_us":"Uses labPBR surface maps; turning it off disables all the material effects below."}}
#define OMNI_ENABLE_PBR
// @option {"label":{"zh_cn":"PBR 标准类型","en_us":"PBR Format"},"description":{"zh_cn":"资源包用的是 labPBR 还是另一种表面贴图编码。","en_us":"Whether the pack stores labPBR or PTGI surface data."},"values":{"0":{"zh_cn":"labPBR","en_us":"labPBR"},"2":{"zh_cn":"PTGI","en_us":"PTGI"}}}
#define OMNI_TEXTURE_PBR_FORMAT 0 // [0 2]
// @option {"label":{"zh_cn":"限制最大粗糙度","en_us":"Clamp High Roughness"},"description":{"zh_cn":"把高粗糙表面的反射直接屏蔽，省性能。","en_us":"Skips reflections on very rough surfaces to save performance."}}
#define OMNI_ROUGHNESS_CLAMP 1 // [0 1]
// @option {"label":{"zh_cn":"限制方块法线强度","en_us":"Terrain Normal Clamp"},"description":{"zh_cn":"压住方块的极端法线，减少噪点。","en_us":"Limits extreme terrain normals to reduce noise."}}
//#define OMNI_TERRAIN_NORMAL_CLAMP
// @option {"label":{"zh_cn":"限制手部法线强度","en_us":"Hand Normal Clamp"},"description":{"zh_cn":"压住手持物的极端法线，减少噪点。","en_us":"Limits extreme hand normals to reduce noise."}}
#define OMNI_HAND_NORMAL_CLAMP
// @option {"label":{"zh_cn":"限制实体法线强度","en_us":"Entity Normal Clamp"},"description":{"zh_cn":"压住实体的极端法线，减少噪点。","en_us":"Limits extreme entity normals to reduce noise."}}
#define OMNI_ENTITIES_NORMAL_CLAMP
// --- 资源包法线的整体强度与材质遮蔽：来源 Eclipse `lib/settings.glsl:371-376`、`dimensions/all_solid.fsh:743-752` ---
// 这一组默认不改变画面：材质遮蔽默认关闭，法线倍率默认一倍与资源包期望一致。
// @option {"label":{"zh_cn":"材质缝隙暗部","en_us":"Material Ambient Occlusion"},"description":{"zh_cn":"用资源包法线贴图的蓝通道当作遮蔽，压暗凹陷处的底色；默认关闭，关闭时画面不变。","en_us":"Uses the resource pack normal map's blue channel as occlusion to darken cavities; off by default so the current look is unchanged."}}
#define OMNI_MATERIAL_AO 0 // [0 1]
// @option {"label":{"zh_cn":"表面纹理强度","en_us":"Normal Map Strength"},"description":{"zh_cn":"资源包法线贴图的整体起伏倍率，一倍为资源包期望的原始强度；默认一倍，画面不变。","en_us":"Overall relief multiplier for resource pack normal maps; 1 is the value packs expect; default 1 leaves the current look unchanged."},"slider":true}
#define OMNI_NORMAL_MAP_MULT 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0]
// @option {"label":{"zh_cn":"透光强度","en_us":"SSS Strength"},"description":{"zh_cn":"光照穿透表面的深度倍率，与偏移一起为零时关闭次表面散射。","en_us":"Depth multiplier of light through the surface; with the offset at zero it disables SSS."},"slider":true}
#define OMNI_SSS_STRENGTH 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 3.0 5.0 7.0 10.0]
// @option {"label":{"zh_cn":"透光偏移","en_us":"SSS Strength Offset"},"description":{"zh_cn":"给穿透深度一个最小值；与倍率一起为零时关闭次表面散射。","en_us":"Minimum value for the light depth; with the multiplier at zero it disables SSS."},"slider":true}
#define OMNI_SSS_STRENGTH_OFFSET 0.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 3.0 5.0 7.0 10.0]
// @option {"label":{"zh_cn":"发光曲线","en_us":"Emissive Gamma"},"description":{"zh_cn":"PBR 自发光的亮暗对比强度，越大反差越明显。","en_us":"Contrast curve of PBR emissiveness; higher is more contrast."},"slider":true}
#define OMNI_EMISSIVENESS_GAMMA 2.2 // [1.0 1.2 1.4 1.6 1.8 2.0 2.2 2.4 2.6 2.8 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0]
// @option {"label":{"zh_cn":"labPBR 孔隙率","en_us":"labPBR Porosity"},"description":{"zh_cn":"使用资源包里的孔隙率通道，决定表面多容易积水。","en_us":"Uses the porosity channel so the surface can puddle more or less."}}
#define OMNI_TEXTURE_PBR_POROSITY 0 // [0 1]
// @option {"label":{"zh_cn":"默认孔隙率","en_us":"Default Porosity"},"description":{"zh_cn":"资源包不给孔隙率时用的值，越小越不吸水、水洼越明显。","en_us":"Porosity when the pack has none; lower means less absorbent and more puddles."},"slider":true}
#define OMNI_TEXTURE_DEFAULT_POROSITY 0.3 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"潮湿反照吸收","en_us":"Wetness Albedo Absorption"},"description":{"zh_cn":"潮湿表面压暗的强度，孔隙率越大越明显。","en_us":"How much wet surfaces darken; stronger with higher porosity."},"slider":true}
#define OMNI_POROSITY_ABSORPTION 0.7 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"禁用手部高光","en_us":"Disable Hand Specular"},"description":{"zh_cn":"去掉手持物的高光，解决某些模组下的反射噪点。","en_us":"Removes held item specular, fixing reflection noise with some mods."}}
//#define OMNI_DISABLE_HAND_SPECULAR
// @option {"label":{"zh_cn":"禁用玩家高光","en_us":"Disable Player Specular"},"description":{"zh_cn":"去掉玩家自身的高光，解决某些模组下的反射噪点。","en_us":"Removes the player's own specular, fixing reflection noise with some mods."}}
//#define OMNI_DISABLE_PLAYER_SPECULAR
// @option {"label":{"zh_cn":"实体顶点法线平滑","en_us":"Entity Vertex Normal Smoothing"},"description":{"zh_cn":"为某些模组提供实体顶点切线与法线，代价很低。","en_us":"Provides entity vertex tangents and normals for some mods; cheap."}}
#define OMNI_ENTITIES_VS_TBN 1 // [0 1]
// @option {"label":{"zh_cn":"方块顶点法线平滑","en_us":"Block Vertex Normal Smoothing"},"description":{"zh_cn":"为某些模组提供方块顶点切线与法线，代价很低。","en_us":"Provides block vertex tangents and normals for some mods; cheap."}}
//#define OMNI_TERRAIN_VS_TBN
// @option {"label":{"zh_cn":"未指定方块按植物处理","en_us":"General Grass Fix"},"description":{"zh_cn":"把倾斜的面都当成植物渲染，可能误伤其他方块。","en_us":"Treats tilted faces as plants; may misfire on other blocks."}}
#define OMNI_GENERAL_GRASS_FIX 0 // [0 1]
// @option {"label":{"zh_cn":"白色调试世界","en_us":"White Debug World"},"page":"about","description":{"zh_cn":"把所有几何的底色改写成纯白，用来检查光照与几何；仅供调试。","en_us":"Rewrites every geometry albedo to plain white for checking lighting and geometry; debug only."}}
//#define OMNI_WHITE_DEBUG_WORLD

// @option {"label":{"zh_cn":"尺寸","en_us":"Puddle size"},"description":{"zh_cn":"低洼处积水范围的大小，调大后水洼更大更连片，调小更零散；来源 Eclipse 的 `Puddle_Size`，默认 1.0 与参考一致。","en_us":"Size of the puddles that form in low spots; larger makes them bigger and better connected. From Eclipse `Puddle_Size`; default 1.0 matches the reference."}}
#define OMNI_PUDDLE_SIZE 1.0 // [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5]
// @option {"label":{"zh_cn":"湿面反射锐度","en_us":"Wet reflection sharpness"},"description":{"zh_cn":"湿表面反射的清晰程度，调大后积水表面更接近镜面；默认 0.0 表示不改动当前粗糙度，Eclipse 默认 0.9。","en_us":"How sharp reflections get on wet ground; larger is more mirror-like. Default 0.0 leaves roughness unchanged; Eclipse default is 0.9."}}
#define OMNI_PUDDLE_REFLECTION_SHARPNESS 0.0 // [0.0 0.9 0.925 0.95 0.975 1.0]

// --- 效果实现：宿主输入、参数换算与阶段入口 ---
// 加载器输入与共用数学先引入；材质解码要用法线曲线，水洼要用相机位置与湿润度。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
// 方块光曲线、材质法线与遮蔽算法放在通用库；这里只传入选项值。
#include "/omni-gfx/surface.glsl"
// 湿面粗糙度与吸水暗化用通用库的水面公式。
#include "/omni-gfx/water.glsl"
// G 缓冲读取、材质编号、掩码与手部判断在绑定层，本文件只保留材质选项与 PBR 解码。
#include "/bind/gbuffer.glsl"
// 水洼要绝对世界坐标与湿润度，由绑定层整理成普通数值。
#include "/bind/camera.glsl"
#include "/bind/weather.glsl"

// --- 水洼：覆盖范围、湿面粗糙度与表面改写 ---
// 水洼覆盖：由湿润度与低洼噪声算出零到一的积水覆盖，供调用方决定水洼范围与暗化强度。
// 为什么先减噪声：噪声代表地势起伏，湿润高于噪声处才是真正低洼，减掉噪声就露出水洼边界。
// 为什么用五次方加指数：让阈值附近的过渡更陡、远离阈值处更平，水洼边缘自然又不整片糊死。
float OmniPuddleCoverage(float halfWet, float noise){
	return ogxPuddleCoverage(halfWet, noise, OMNI_PUDDLE_SIZE); // 覆盖公式在通用库，尺寸选项在这里传入。
}

// 湿面反射锐度：把干表面粗糙度往「湿表面粗糙度」混合，湿得越深反射越清晰。
// `OMNI_PUDDLE_REFLECTION_SHARPNESS` 就是混合比例的上限，默认 0.0 时原样返回，不改变画面。
// 数学与 Eclipse 一致：`mix(roughness, wetRoughness, wetnessStages * 锐度)`，此处不做额外夹取，保持等价。
// 调用点：`effects/shared/surface.glsl` 的 `MaterialFromTex`（湿润度取那里的 `wet`）与本文件的 `OmniPuddleSurface`（传水洼权重）。
float OmniPuddleRoughness(float roughness, float wetRoughness, float wetnessStages){
	return mix(roughness, wetRoughness, wetnessStages * OMNI_PUDDLE_REFLECTION_SHARPNESS); // 湿润阶段乘锐度作为混合比例。
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

// --- 材质：把资源包的底色、法线、表面三张贴图解码成光照要用的表面数据 ---
// 来源：照 iterationT `Lib/GbufferData.glsl` 移植；G 缓冲读取、材质编号、掩码与手部/实体判断的实现都在 `bind/gbuffer.glsl`。
// 调用位置：合成阶段片元先 `GetGbufferData()`，再 `CalculateMasks`、`FixParticleMask`、`ApplyMaterial`；
// 几何阶段片元要对法线应用材质遮蔽与起伏倍率时调用 `omniMaterialNormal`。

// 从表面贴图解出材质：孔隙率、金属、自发光与散射的通道解释在绑定层，本文件只把选项接进去。
// 参数 `wet` 是这一处的湿润度，`baseTex` 会被吸水压暗，所以是 `inout`。
Material MaterialFromTex(inout vec3 baseTex, vec4 specTex, float wet){
	return bind_material_from_tex(baseTex, specTex, wet, bool(OMNI_TEXTURE_PBR_POROSITY), OMNI_TEXTURE_PBR_FORMAT,
		OMNI_TEXTURE_DEFAULT_POROSITY, OMNI_POROSITY_ABSORPTION, bool(OMNI_ROUGHNESS_CLAMP), OMNI_EMISSIVENESS_GAMMA,
		OMNI_SSS_STRENGTH, OMNI_SSS_STRENGTH_OFFSET, OMNI_PUDDLE_REFLECTION_SHARPNESS); // 解码公式在绑定层。
}
// 从各号画面读回一个像素的完整表面数据，供合成阶段使用。
// 调用前提：调用方必须先声明整数像素坐标 `texelCoord`。
#if defined OMNI_COMPOSITE0_PASS || defined OMNI_COMPOSITE1_PASS || defined OMNI_COMPOSITE2_PASS || defined OMNI_COMPOSITE3_PASS || defined OMNI_COMPOSITE4_PASS || defined OMNI_COMPOSITE5_PASS
GbufferData GetGbufferData(){
	GbufferData data = bind_gbuffer(texelCoord, colortex0, colortex3, colortex4, colortex5, colortex6, depthtex1, depthtex0); // 画面通道含义在绑定层解释。
	#ifdef OMNI_ENABLE_PBR // 开启物理光照时才解材质，否则当作空气。
		data.material = MaterialFromTex(data.albedo, data.specTex, data.wet); // 解出材质，同时压暗吸水底色。
		#if MC_VERSION < 11605
			data.material.reflectionStrength *= float(bind_is_world_depth(data.depthW)); // 旧版没有单独的半透明深度，天空像素不该反射。
		#endif
	#else
		data.material = airMaterial; // 关闭物理光照时统一按空气处理。
	#endif
	return data; // 交回读回的数据。
}
#endif // 合成阶段读回段结束。
// --- 材质掩码：实现与手部/实体判断都在绑定层，这里保留原调用名做一次转发 ---
MaterialMask CalculateMasks(float materialIDs){
	return bind_material_mask(materialIDs); // 材质编号到类别在绑定层解释。
}
// 粒子修正并带深度：粒子很薄，读回时会落到后面的几何上，所以把半透明层也标记成粒子并借用不透明深度。
void FixParticleMask(inout MaterialMask solidMask, inout MaterialMask mask, inout float depthL, in float depthW){
	bind_fix_particle_mask(solidMask, mask, depthL, depthW); // 修正规则在绑定层。
}
// 粒子修正：同上，但不改深度，供不需要深度的阶段使用。
void FixParticleMask(inout MaterialMask solidMask, inout MaterialMask mask){
	bind_fix_particle_mask(solidMask, mask); // 修正规则在绑定层。
}
// 用固定材质覆盖解码材质：水、染色玻璃与冰用写死的参数，并标记为光滑面。
void ApplyMaterial(inout Material material, in MaterialMask mask, inout bool isSmooth){
	bind_apply_material(material, mask, isSmooth); // 固定材质在绑定层。
}
// 资源包材质处理：把法线贴图的原始颜色解成切线空间法线，并按选项缩放起伏、导出材质遮蔽。
// 对应 Eclipse `dimensions/all_solid.fsh:204-210`（`applyBump` 里的 `NORMAL_MAP_MULT`）与 `:743-745`（`MATERIAL_AO`）。
// 为什么单独成一个函数：几何阶段（地形、实体、方块、手）都要在同一处对法线做这两步，
//   合并成一个纯函数，每个调用点只把现有 `DecodeNormalTex` 换成它，避免各写一份倍率与遮蔽。
// 为什么仍复用 `common/math.glsl` 的 `DecodeNormalTex`：那是全项目唯一的法线解码口径，另起一份会与别处不一致。
// 返回值：`xyz` 是单位切线空间法线；`w` 是可乘到底色上的遮蔽系数，未开材质遮蔽时恒为一。
// 材质遮蔽：资源包把遮蔽存在法线贴图的蓝通道，取出来乘到底色上；未开该选项时恒为一。
// 为什么单独拆出来：视差路径已经自己解出法线，只差遮蔽要另外取一次贴图，拆开才能单独复用。
float omniMaterialAO(vec3 normalTexRGB){
	return ogxMaterialAo(normalTexRGB, bool(OMNI_MATERIAL_AO)); // 选项决定是否启用遮蔽。
}
// 法线倍率：围绕朝外方向缩放起伏，`OMNI_NORMAL_MAP_MULT` 越大起伏越强；为一等于原样。
// 传入的已经是切线空间单位法线，所以视差路径解出的法线也能直接套用，不必重采贴图。
vec3 omniMaterialNormalScale(vec3 tangentNormal){
	return ogxMaterialNormalScale(tangentNormal, OMNI_NORMAL_MAP_MULT); // 倍率由选项传入。
}
vec4 omniMaterialNormal(vec3 normalTexRGB){
	return ogxMaterialNormal(normalTexRGB, bool(OMNI_MATERIAL_AO), OMNI_NORMAL_MAP_MULT); // 解码、缩放与遮蔽一次完成。
}
// 视差由使用它的几何阶段显式引入，本文件只提供材质解码与选项，不反向依赖渲染层。
#endif // OMNI_SHARED_SURFACE_INCLUDED

