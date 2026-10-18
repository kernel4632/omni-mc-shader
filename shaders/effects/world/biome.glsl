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

#ifndef OMNI_BIOME_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_BIOME_INCLUDED // 置上标记，后续再次引用直接跳过。

// @effect {"label":{"zh_cn":"群系环境","en_us":"Biome environment"}}
// @option {"label":{"zh_cn":"群系特色环境","en_us":"Per-biome environment"},"description":{"zh_cn":"按玩家所在群系给体积雾换雾色与雾密度，来自 Eclipse；默认关闭，打开后沼泽、丛林、黑森林、苍白花园画面会变化。","en_us":"Swaps volumetric fog colour and density by the player's biome, from Eclipse; off by default."}}
#define OMNI_PER_BIOME_ENV 0 // [0 1]
// @option {"label":{"zh_cn":"沼泽环境","en_us":"Swamp environment"},"description":{"zh_cn":"只切换沼泽这一类群系的环境；总开关打开后才生效，其他群系环境不受影响。","en_us":"Toggles the environment only for swamp-like biomes; only active once the master switch is on."}}
#define OMNI_SWAMP_ENV 1 // [0 1]
// @option {"label":{"zh_cn":"丛林环境","en_us":"Jungle environment"},"description":{"zh_cn":"只切换丛林这一类群系的环境；总开关打开后才生效，其他群系环境不受影响。","en_us":"Toggles the environment only for jungle-like biomes; only active once the master switch is on."}}
#define OMNI_JUNGLE_ENV 1 // [0 1]
// @option {"label":{"zh_cn":"黑森林环境","en_us":"Dark forest environment"},"description":{"zh_cn":"只切换黑森林这一种群系的环境；总开关打开后才生效，其他群系环境不受影响。","en_us":"Toggles the environment only for dark forest; only active once the master switch is on."}}
#define OMNI_DARKFOREST_ENV 1 // [0 1]
// @option {"label":{"zh_cn":"苍白花园环境","en_us":"Pale garden environment"},"description":{"zh_cn":"只切换苍白花园这一种群系的环境；总开关打开后才生效，其他群系环境不受影响。","en_us":"Toggles the environment only for the pale garden; only active once the master switch is on."}}
#define OMNI_PALE_GARDEN_ENV 1 // [0 1]
// @option {"label":{"zh_cn":"沼泽雾密度","en_us":"Swamp fog density"},"description":{"zh_cn":"沼泽里“仅高度衰减”那层雾的密度标度，只在沼泽环境开启时生效。","en_us":"Density scale of the height-only fog layer in swamps; used only when the swamp environment is on."},"slider":true}
#define OMNI_SWAMP_FOG_DENSITY 0.3 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.22 0.25 0.28 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"沼泽多云雾密度","en_us":"Swamp wispy fog density"},"description":{"zh_cn":"沼泽里“团雾”那层雾的密度标度，只在沼泽环境开启时生效。","en_us":"Density scale of the wispy fog layer in swamps; used only when the swamp environment is on."},"slider":true}
#define OMNI_SWAMP_FOG_CLOUDY_DENSITY 0.0 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.22 0.25 0.28 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"沼泽雾色红","en_us":"Swamp fog red"},"description":{"zh_cn":"沼泽雾的红色分量，与另外两个分量一起决定雾色，只在沼泽环境开启时生效。","en_us":"Red component of the swamp fog colour; used only when the swamp environment is on."},"slider":true}
#define OMNI_SWAMP_FOG_COLOR_R 0.15 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"沼泽雾色绿","en_us":"Swamp fog green"},"description":{"zh_cn":"沼泽雾的绿色分量，与另外两个分量一起决定雾色，只在沼泽环境开启时生效。","en_us":"Green component of the swamp fog colour; used only when the swamp environment is on."},"slider":true}
#define OMNI_SWAMP_FOG_COLOR_G 0.25 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"沼泽雾色蓝","en_us":"Swamp fog blue"},"description":{"zh_cn":"沼泽雾的蓝色分量，与另外两个分量一起决定雾色，只在沼泽环境开启时生效。","en_us":"Blue component of the swamp fog colour; used only when the swamp environment is on."},"slider":true}
#define OMNI_SWAMP_FOG_COLOR_B 0.05 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"丛林雾密度","en_us":"Jungle fog density"},"description":{"zh_cn":"丛林里“仅高度衰减”那层雾的密度标度，只在丛林环境开启时生效。","en_us":"Density scale of the height-only fog layer in jungles; used only when the jungle environment is on."},"slider":true}
#define OMNI_JUNGLE_FOG_DENSITY 0.1 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.22 0.25 0.28 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"丛林多云雾密度","en_us":"Jungle wispy fog density"},"description":{"zh_cn":"丛林里“团雾”那层雾的密度标度，只在丛林环境开启时生效。","en_us":"Density scale of the wispy fog layer in jungles; used only when the jungle environment is on."},"slider":true}
#define OMNI_JUNGLE_FOG_CLOUDY_DENSITY 0.02 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.22 0.25 0.28 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"丛林雾色红","en_us":"Jungle fog red"},"description":{"zh_cn":"丛林雾的红色分量，与另外两个分量一起决定雾色，只在丛林环境开启时生效。","en_us":"Red component of the jungle fog colour; used only when the jungle environment is on."},"slider":true}
#define OMNI_JUNGLE_FOG_COLOR_R 0.5 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"丛林雾色绿","en_us":"Jungle fog green"},"description":{"zh_cn":"丛林雾的绿色分量，与另外两个分量一起决定雾色，只在丛林环境开启时生效。","en_us":"Green component of the jungle fog colour; used only when the jungle environment is on."},"slider":true}
#define OMNI_JUNGLE_FOG_COLOR_G 1.0 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"丛林雾色蓝","en_us":"Jungle fog blue"},"description":{"zh_cn":"丛林雾的蓝色分量，与另外两个分量一起决定雾色，只在丛林环境开启时生效。","en_us":"Blue component of the jungle fog colour; used only when the jungle environment is on."},"slider":true}
#define OMNI_JUNGLE_FOG_COLOR_B 0.8 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"黑森林雾密度","en_us":"Dark forest fog density"},"description":{"zh_cn":"黑森林里“仅高度衰减”那层雾的密度标度，只在黑森林环境开启时生效。","en_us":"Density scale of the height-only fog layer in dark forests; used only when the dark forest environment is on."},"slider":true}
#define OMNI_DARKFOREST_FOG_DENSITY 0.1 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.22 0.25 0.28 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"黑森林多云雾密度","en_us":"Dark forest wispy fog density"},"description":{"zh_cn":"黑森林里“团雾”那层雾的密度标度，只在黑森林环境开启时生效。","en_us":"Density scale of the wispy fog layer in dark forests; used only when the dark forest environment is on."},"slider":true}
#define OMNI_DARKFOREST_FOG_CLOUDY_DENSITY 0.05 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.22 0.25 0.28 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"黑森林雾色红","en_us":"Dark forest fog red"},"description":{"zh_cn":"黑森林雾的红色分量，与另外两个分量一起决定雾色，只在黑森林环境开启时生效。","en_us":"Red component of the dark forest fog colour; used only when the dark forest environment is on."},"slider":true}
#define OMNI_DARKFOREST_FOG_COLOR_R 0.3 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"黑森林雾色绿","en_us":"Dark forest fog green"},"description":{"zh_cn":"黑森林雾的绿色分量，与另外两个分量一起决定雾色，只在黑森林环境开启时生效。","en_us":"Green component of the dark forest fog colour; used only when the dark forest environment is on."},"slider":true}
#define OMNI_DARKFOREST_FOG_COLOR_G 0.4 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"黑森林雾色蓝","en_us":"Dark forest fog blue"},"description":{"zh_cn":"黑森林雾的蓝色分量，与另外两个分量一起决定雾色，只在黑森林环境开启时生效。","en_us":"Blue component of the dark forest fog colour; used only when the dark forest environment is on."},"slider":true}
#define OMNI_DARKFOREST_FOG_COLOR_B 1.0 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"苍白花园雾密度","en_us":"Pale garden fog density"},"description":{"zh_cn":"苍白花园里“仅高度衰减”那层雾的密度标度，只在苍白花园环境开启时生效。","en_us":"Density scale of the height-only fog layer in the pale garden; used only when the pale garden environment is on."},"slider":true}
#define OMNI_PALE_GARDEN_FOG_DENSITY 0.13 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.22 0.25 0.28 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"苍白花园多云雾密度","en_us":"Pale garden wispy fog density"},"description":{"zh_cn":"苍白花园里“团雾”那层雾的密度标度，只在苍白花园环境开启时生效。","en_us":"Density scale of the wispy fog layer in the pale garden; used only when the pale garden environment is on."},"slider":true}
#define OMNI_PALE_GARDEN_FOG_CLOUDY_DENSITY 0.4 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.22 0.25 0.28 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"苍白花园雾色红","en_us":"Pale garden fog red"},"description":{"zh_cn":"苍白花园雾的红色分量，与另外两个分量一起决定雾色，只在苍白花园环境开启时生效。","en_us":"Red component of the pale garden fog colour; used only when the pale garden environment is on."},"slider":true}
#define OMNI_PALE_GARDEN_FOG_COLOR_R 0.4 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"苍白花园雾色绿","en_us":"Pale garden fog green"},"description":{"zh_cn":"苍白花园雾的绿色分量，与另外两个分量一起决定雾色，只在苍白花园环境开启时生效。","en_us":"Green component of the pale garden fog colour; used only when the pale garden environment is on."},"slider":true}
#define OMNI_PALE_GARDEN_FOG_COLOR_G 0.4 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"苍白花园雾色蓝","en_us":"Pale garden fog blue"},"description":{"zh_cn":"苍白花园雾的蓝色分量，与另外两个分量一起决定雾色，只在苍白花园环境开启时生效。","en_us":"Blue component of the pale garden fog colour; used only when the pale garden environment is on."},"slider":true}
#define OMNI_PALE_GARDEN_FOG_COLOR_B 0.6 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]

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
	coverage = clamp(weights.x + weights.y + weights.z + weights.w, 0.0, 1.0); // 群系覆盖程度，零表示不在任何已启用群系内。
	biomeColor = vec3(0.0); // 从黑色起累加，没落在群系里就保持黑色（调用方再按覆盖程度决定是否使用）。
	biomeColor.r = weights.w * OMNI_PALE_GARDEN_FOG_COLOR_R + weights.x * OMNI_SWAMP_FOG_COLOR_R + weights.y * OMNI_JUNGLE_FOG_COLOR_R + weights.z * OMNI_DARKFOREST_FOG_COLOR_R; // 红色分量按权重相加。
	biomeColor.g = weights.w * OMNI_PALE_GARDEN_FOG_COLOR_G + weights.x * OMNI_SWAMP_FOG_COLOR_G + weights.y * OMNI_JUNGLE_FOG_COLOR_G + weights.z * OMNI_DARKFOREST_FOG_COLOR_G; // 绿色分量按权重相加。
	biomeColor.b = weights.w * OMNI_PALE_GARDEN_FOG_COLOR_B + weights.x * OMNI_SWAMP_FOG_COLOR_B + weights.y * OMNI_JUNGLE_FOG_COLOR_B + weights.z * OMNI_DARKFOREST_FOG_COLOR_B; // 蓝色分量按权重相加。
}

// 群系雾密度：把“仅高度衰减”和“团雾”两套密度标度朝本群系的取值混合，来源 Eclipse 的 `BiomeFogDensity`。
// `maxDistance` 是随离相机距离收敛的包络：近处替换成群系密度，远处退回原来的密度，避免整屏都被改写。
// 为什么两套一起算：`VolumetricFog` 当前只用其中一套，但两套都更新，切换雾类型时不必改这里。
void omniBiomeFogDensity(vec4 weights, inout float uniformDensity, inout float cloudyDensity, float maxDistance){
	float inBiome = clamp(weights.x + weights.y + weights.z + weights.w, 0.0, 1.0); // 落在任一已启用群系内的程度。
	float biomeUniform = weights.x * OMNI_SWAMP_FOG_DENSITY + weights.y * OMNI_JUNGLE_FOG_DENSITY + weights.z * OMNI_DARKFOREST_FOG_DENSITY + weights.w * OMNI_PALE_GARDEN_FOG_DENSITY; // 各群系高度衰减雾密度加权和。
	float biomeCloudy = weights.w * OMNI_PALE_GARDEN_FOG_CLOUDY_DENSITY + weights.x * OMNI_SWAMP_FOG_CLOUDY_DENSITY + weights.y * OMNI_JUNGLE_FOG_CLOUDY_DENSITY + weights.z * OMNI_DARKFOREST_FOG_CLOUDY_DENSITY; // 各群系团雾密度加权和。

	float blend = inBiome * maxDistance; // 群系内且靠近相机时才替换，远处的权重被包络压回零。
	uniformDensity = mix(uniformDensity, biomeUniform, blend); // 高度衰减雾的密度标度朝群系值混合。
	cloudyDensity = mix(cloudyDensity, biomeCloudy, blend); // 团雾的密度标度朝群系值混合。
}

#endif // 总开关块结束。
#endif // 文件守卫结束。
