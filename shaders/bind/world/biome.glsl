/*
群系环境的宿主接线：读取 Minecraft 输入、调用通用库并写出结果。
调用位置：原引用 `effects/world/biome.glsl` 的程序改为引用本文件。
可复制示例：下方函数保留原有效果入口的签名，调用方式不变。
设计原因与取舍：选项留在效果层，算法在通用库，本文件只做宿主数据与算法之间的转换。
*/
#ifndef OMNI_BIND_WORLD_BIOME_INCLUDED
#define OMNI_BIND_WORLD_BIOME_INCLUDED
#include "/effects/world/biome.glsl"
// 群系雾色与雾密度的加权混合在通用库，本文件只把四个权重与选项常量传进去。
#include "/omni-gfx/fog/fog.glsl"
/*
群系特色环境：按玩家所在生物群系，给体积雾换一套雾色与雾密度，来源是 Eclipse 的每群系环境（`PER_BIOME_ENVIRONMENT`）。
调用位置：
  `effects/fog/fog.glsl` 的 `VolumetricFog` 在算雾密度与雾色时调用本文件；本文件由那份文件引用一次，不直接出现在入口。
可复制示例：
  在 `effects/fog/fog.glsl` 内写 `#include "/effects/world/biome.glsl"`，之后即可调用下面的函数。
  `vec4 w = omniBiomeWeights();`                                        取四个群系的权重
  `omniBiomeFogColor(w, biomeColor, coverage);`                         取本群系合成的雾色与覆盖程度
  `omniBiomeFogDensity(w, uniformDensity, cloudyDensity, envelope);`    把两套密度系数朝本群系混合
设计原因与取舍：
  Eclipse 用加载器每帧算好的群系权重（`isSwamps` 等）判断当前所在群系，并在切换群系时按六十秒平滑过渡，
  避免颜色突变。本项目沿用同一条加载器通路：权重由 `rendering/pipeline.properties` 的自定义输入注入，
  本文件只声明同名 `uniform` 再读取，不自己维护群系判断与平滑，也不硬塞群系编号。
  需要主助手在 `rendering/pipeline.properties` 登记的四个自定义输入（名字一一对应下面的声明）：
  `BiomeSwampSmooth`、`BiomeJungleSmooth`、`BiomeDarkForestSmooth`、`BiomePaleGardenSmooth`。
  为什么会有一条对外依赖：加载器只把自定义输入绑到“真的声明了该名字”的程序上，GLSL 不声明就拿不到值。
  未登记时这些 `uniform` 取零，总开关打开也只是不改变画面，不会报错，缺这四行之前不影响默认画面。
  Eclipse 默认开启且会改变画面，本项目按“默认中性”约定把总开关默认关闭；四个群系开关保持与 Eclipse 相同的
  默认开启，但它们只在总开关打开后才参与计算，所以默认画面与原来完全一致。
  Eclipse 的沙尘暴与雪暴两项（`sandStorm`、`snowStorm`）属于另外的独立能力，这里按同一份对照口径不纳入；
  因此沼泽、丛林、黑森林、苍白花园四个群系之外不会有额外影响。
*/



#if OMNI_PER_BIOME_ENV // 总开关关闭时本文件不产生任何代码，默认画面与原来一致。

// 四个群系权重：由加载器每帧算好并平滑，本文件只声明同名 `uniform` 再读取。
// 为什么在 GLSL 里也要声明：加载器只把自定义输入绑到真的声明了该名字的程序上，不声明就取不到值。
// 取不到时这些量恒为零，函数返回零权重，不会报错也不会改变画面。
uniform float BiomeSwampSmooth; // 沼泽权重，零到一。
uniform float BiomeJungleSmooth; // 丛林权重，零到一。
uniform float BiomeDarkForestSmooth; // 黑森林权重，零到一。
uniform float BiomePaleGardenSmooth; // 苍白花园权重，零到一。

// 把四个群系的权重打包成 `vec4` 返回：`x` 沼泽、`y` 丛林、`z` 黑森林、`w` 苍白花园。
// 为什么打包：雾色与雾密度都要这套权重，每像素算一次即可，避免两处各判断一遍。
// 为什么每个开关单独判断：关闭的群系取零权重，等于从这个群系环境里消失，不影响其他群系。
vec4 omniBiomeWeights(){
	float swamp = 0.0; // 沼泽权重，默认零。
	float jungle = 0.0; // 丛林权重，默认零。
	float darkForest = 0.0; // 黑森林权重，默认零。
	float paleGarden = 0.0; // 苍白花园权重，默认零。

	#if OMNI_SWAMP_ENV // 沼泽开关打开才读取它这一路权重。
		swamp = BiomeSwampSmooth; // 沼泽权重来自加载器的群系类别判断。
	#endif
	#if OMNI_JUNGLE_ENV // 丛林开关打开才读取它这一路权重。
		jungle = BiomeJungleSmooth; // 丛林权重来自加载器的群系类别判断。
	#endif
	#if OMNI_DARKFOREST_ENV // 黑森林开关打开才读取它这一路权重。
		darkForest = BiomeDarkForestSmooth; // 黑森林权重来自加载器的具体群系判断。
	#endif
	#if OMNI_PALE_GARDEN_ENV // 苍白花园开关打开才读取它这一路权重。
		paleGarden = BiomePaleGardenSmooth; // 苍白花园权重来自加载器的具体群系判断。
	#endif

	return vec4(swamp, jungle, darkForest, paleGarden); // 打包交回，供雾色与雾密度共用。
}

// 群系雾色：把四个群系的配色按权重加权求和，带回合成后的颜色与“是否落在群系内”的程度。
// 来源 Eclipse 的 `BiomeVLFogColors`（去掉沙尘暴、雪暴两项）。
// 为什么直接加权求和：四个群系互斥，权重之和最多为一，相加即得本群系配色，不必写分支。
// 颜色分量分开写，是为了让它和 Eclipse 原式一行对一行，方便之后逐行核对。
void omniBiomeFogColor(vec4 weights, out vec3 biomeColor, out float coverage){
	biomeColor = ogxBiomeFogColor(weights, vec3(OMNI_PALE_GARDEN_FOG_COLOR_R, OMNI_PALE_GARDEN_FOG_COLOR_G, OMNI_PALE_GARDEN_FOG_COLOR_B),
		vec3(OMNI_SWAMP_FOG_COLOR_R, OMNI_SWAMP_FOG_COLOR_G, OMNI_SWAMP_FOG_COLOR_B),
		vec3(OMNI_JUNGLE_FOG_COLOR_R, OMNI_JUNGLE_FOG_COLOR_G, OMNI_JUNGLE_FOG_COLOR_B),
		vec3(OMNI_DARKFOREST_FOG_COLOR_R, OMNI_DARKFOREST_FOG_COLOR_G, OMNI_DARKFOREST_FOG_COLOR_B), coverage); // 颜色加权在通用库，覆盖程度一并交回。
}

// 群系雾密度：把“仅高度衰减”和“团雾”两套密度标度朝本群系的取值混合，来源 Eclipse 的 `BiomeFogDensity`。
// `maxDistance` 是随离相机距离收敛的包络：近处替换成群系密度，远处退回原来的密度，避免整屏都被改写。
// 为什么两套一起算：`VolumetricFog` 当前只用其中一套，但两套都更新，切换雾类型时不必改这里。
void omniBiomeFogDensity(vec4 weights, inout float uniformDensity, inout float cloudyDensity, float maxDistance){
	ogxBiomeFogDensity(weights, uniformDensity, cloudyDensity,
		OMNI_SWAMP_FOG_DENSITY, OMNI_JUNGLE_FOG_DENSITY, OMNI_DARKFOREST_FOG_DENSITY, OMNI_PALE_GARDEN_FOG_DENSITY,
		OMNI_SWAMP_FOG_CLOUDY_DENSITY, OMNI_JUNGLE_FOG_CLOUDY_DENSITY, OMNI_DARKFOREST_FOG_CLOUDY_DENSITY, OMNI_PALE_GARDEN_FOG_CLOUDY_DENSITY,
		maxDistance); // 两套密度与包络混合在通用库。
}

#endif // 总开关块结束。
#endif // OMNI_BIND_WORLD_BIOME_INCLUDED
