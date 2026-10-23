/*
群系环境的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/world/biome.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/world/biome.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_WORLD_BIOME_INCLUDED
#define OMNI_EFFECT_WORLD_BIOME_INCLUDED
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
#endif // 选项层结束
