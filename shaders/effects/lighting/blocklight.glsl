/*
方块光与手持光的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/lighting/blocklight.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/lighting/blocklight.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_LIGHTING_BLOCKLIGHT_INCLUDED
#define OMNI_EFFECT_LIGHTING_BLOCKLIGHT_INCLUDED
// @effect {"label":{"zh_cn":"方块光与手持光","en_us":"Block & held light"}}
// @option {"label":{"zh_cn":"方块光强度","en_us":"Block light brightness"},"description":{"zh_cn":"光源方块自身发光与照亮周围的强度，同时影响资源包自发光的强度。","en_us":"Brightness of light sources and the area they light; also scales resource-pack emissiveness."},"slider":true}
#define OMNI_TORCHLIGHT_BRIGHTNESS 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label":{"zh_cn":"方块光色温","en_us":"Block light temperature"},"description":{"zh_cn":"光源方块发光与照亮周围的色温，单位开尔文；只改颜色不改强度。","en_us":"Colour temperature of block light in kelvin; changes colour only, not brightness."},"slider":true}
#define OMNI_TORCHLIGHT_COLOR_TEMPERATURE 3000 // [2000 2500 3000 3500 4000 4500 5000 5500 6000 6500 7000 7500 8000 8500 9000 9500 10000 12000 15000]
// @option {"label":{"zh_cn":"指向性方块光","en_us":"Directional block light"},"description":{"zh_cn":"在法线贴图上显示光照方向；需要支持法线贴图的资源包，可能出现光照衔接错误。","en_us":"Shows the light direction on normal maps; needs a normal-map pack and may show seams."}}
#define OMNI_DIRECTIONAL_BLOCKLIGHT 0 // [0 1]
// @option {"label":{"zh_cn":"指向性权重","en_us":"Directional strength"},"description":{"zh_cn":"指向性方块光的强度；调大方向感更强，光照衔接错误也更明显。","en_us":"Strength of directional block light; larger is more directional and shows more seams."},"slider":true}
#define OMNI_DIRECTIONAL_BLOCKLIGHT_STRENGTH 0.5 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"发光贴图模式","en_us":"Emissive mode"},"description":{"zh_cn":"硬编码发光、资源包 PBR 发光，或两者相加。","en_us":"Hardcoded emissive, resource-pack PBR emissive, or both added."},"values":{"0":{"zh_cn":"仅硬编码","en_us":"Hardcoded only"},"1":{"zh_cn":"仅PBR贴图","en_us":"PBR only"},"2":{"zh_cn":"PBR贴图 + 硬编码","en_us":"PBR + hardcoded"}}}
#define OMNI_TEXTURE_EMISSIVENESS_MODE 2 // [0 1 2]
// @option {"label":{"zh_cn":"硬编码亮度","en_us":"Hardcoded brightness"},"description":{"zh_cn":"按方块类型写死的自发光强度。","en_us":"Emissive strength baked in by block type."},"slider":true}
#define OMNI_TEXTURE_BRIGHTNESS 1.0 // [0.0 0.1 0.2 0.3 0.5 0.7 1.0 1.5 2.0 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 70.0 100.0]
// @option {"label":{"zh_cn":"PBR贴图亮度","en_us":"PBR emissive brightness"},"description":{"zh_cn":"资源包自发光贴图的整体亮度。","en_us":"Overall brightness of the resource-pack emissive map."},"slider":true}
#define OMNI_EMISSIVENESS_BRIGHTNESS 1.0 // [0.0 0.1 0.2 0.3 0.5 0.7 1.0 1.5 2.0 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 70.0 100.0]
// @option {"label":{"zh_cn":"手持光源模式","en_us":"Held light mode"},"description":{"zh_cn":"火把是随视角的球形光，手电筒是朝前的一束光。","en_us":"Torch is a view-centred glow, flashlight is a forward beam."},"values":{"0":{"zh_cn":"火把","en_us":"Torch"},"1":{"zh_cn":"手电筒","en_us":"Flashlight"}}}
#define OMNI_HELDLIGHT_MODE 0 // [0 1]
// @option {"label":{"zh_cn":"手持光源强度","en_us":"Held light brightness"},"description":{"zh_cn":"手持光源的整体强度。","en_us":"Overall brightness of the held light."},"slider":true}
#define OMNI_HELDLIGHT_BRIGHTNESS 1.0 // [0.0 0.1 0.15 0.2 0.3 0.5 0.7 1.0 1.5 2.0 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 70.0 100.0]
// @option {"label":{"zh_cn":"火把衰减系数","en_us":"Torch falloff"},"description":{"zh_cn":"火把模式下亮度随距离衰减的快慢；调大衰减更快。","en_us":"How fast torch-mode brightness falls with distance; larger fades faster."},"slider":true}
#define OMNI_HELDLIGHT_FALLOFF 1.8 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.4 1.6 1.8 2.0]
// @option {"label":{"zh_cn":"手持光投阴影","en_us":"Held light shadow"},"description":{"zh_cn":"让手持光源投射屏幕空间阴影，可能出现轻微的错误遮挡。","en_us":"Lets the held light cast screen-space shadows; may show slight wrong occlusion."}}
#define OMNI_HELDLIGHT_SHADOW
// @option {"label":{"zh_cn":"手持光阴影强度","en_us":"Held light shadow strength"},"description":{"zh_cn":"手持光源投下阴影的最大变暗程度，一为全黑、零不压暗；零点八五与原来一致，对应 Eclipse 的 LPV_HANDHELD_SHADOWS_STRENGTH。","en_us":"Maximum darkening of the held light's shadow; 1 is fully dark, 0 does not darken; 0.85 matches the old look; matches Eclipse's LPV_HANDHELD_SHADOWS_STRENGTH."},"slider":true}
#define OMNI_HELDLIGHT_SHADOW_STRENGTH 0.85 // [0.0 0.25 0.5 0.6 0.7 0.75 0.8 0.825 0.85 0.875 0.9 0.925 0.95 0.975 1.0]
// @option {"label":{"zh_cn":"手持光阴影质量","en_us":"Held light shadow quality"},"description":{"zh_cn":"手持光屏幕阴影的步数，高更精细也更慢；对应 Eclipse 的 LPV_HANDHELD_SHADOWS_QUALITY。","en_us":"Steps of the held light's screen shadow; high is finer and slower; matches Eclipse's LPV_HANDHELD_SHADOWS_QUALITY."},"values":{"0":{"zh_cn":"低","en_us":"Low"},"1":{"zh_cn":"高","en_us":"High"}}}
#define OMNI_HELDLIGHT_SHADOW_QUALITY 0 // [0 1]
// @option {"label":{"zh_cn":"手持光影响高光","en_us":"Held light specular"},"description":{"zh_cn":"把手持光源映到表面高光上；需要支持高光贴图的资源包并开启 PBR。","en_us":"Maps the held light into surface specular; needs a specular-map pack with PBR on."}}
#define OMNI_SPECULAR_HELDLIGHT
// @option {"label":{"zh_cn":"手电筒光束角度","en_us":"Flashlight FOV"},"description":{"zh_cn":"手电筒照亮范围的大小。","en_us":"Size of the flashlight's lit cone."},"slider":true}
#define OMNI_FLASHLIGHT_FOV 0.25 // [0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5]
// @option {"label":{"zh_cn":"手电筒衰减系数","en_us":"Flashlight falloff"},"description":{"zh_cn":"手电筒模式下亮度随距离衰减的快慢；调大衰减更快。","en_us":"How fast flashlight brightness falls with distance; larger fades faster."},"slider":true}
#define OMNI_FLASHLIGHT_HELDLIGHT_FALLOFF 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.4 1.6 1.8 2.0]
// @option {"label":{"zh_cn":"手电筒指向平滑","en_us":"Flashlight aim smoothing"},"description":{"zh_cn":"让手电筒指向滞后于视角变化，转头时光束不会瞬间跟到底。","en_us":"Makes the flashlight aim lag behind camera turns so the beam does not snap."}}
#define OMNI_FLASHLIGHT_CAMERA_SMOOTH 1 // [0 1]
// @option {"label":{"zh_cn":"手电筒过渡时长","en_us":"Flashlight aim time"},"description":{"zh_cn":"手电筒指向平滑的过渡时间，单位秒。","en_us":"Transition time of the aim smoothing in seconds."},"slider":true}
#define OMNI_FLASHLIGHT_CAMERA_SMOOTH_TIME 10.0 // [5.0 7.0 10.0 15.0 20.0 30.0 50.0]
// @option {"label":{"zh_cn":"手电筒颜色-红","en_us":"Flashlight colour - R"},"description":{"zh_cn":"手电筒光束的红色分量。","en_us":"Red channel of the flashlight beam."},"slider":true}
#define OMNI_FLASHLIGHT_COLOR_R 1.0 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
// @option {"label":{"zh_cn":"手电筒颜色-绿","en_us":"Flashlight colour - G"},"description":{"zh_cn":"手电筒光束的绿色分量。","en_us":"Green channel of the flashlight beam."},"slider":true}
#define OMNI_FLASHLIGHT_COLOR_G 1.0 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
// @option {"label":{"zh_cn":"手电筒颜色-蓝","en_us":"Flashlight colour - B"},"description":{"zh_cn":"手电筒光束的蓝色分量。","en_us":"Blue channel of the flashlight beam."},"slider":true}
#define OMNI_FLASHLIGHT_COLOR_B 1.0 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
// @option {"label":{"zh_cn":"水平位置-左持","en_us":"Horizontal offset - left"},"description":{"zh_cn":"左手手电筒灯源的水平位置，正值方向为右。","en_us":"Horizontal position of the left-hand light, positive is right."},"slider":true}
#define OMNI_FLASHLIGHT_POS_L_X -0.25 // [-1.0 -0.9 -0.8 -0.7 -0.6 -0.5 -0.45 -0.4 -0.35 -0.3 -0.25 -0.2 -0.15 -0.1 -0.05 0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"垂直位置-左持","en_us":"Vertical offset - left"},"description":{"zh_cn":"左手手电筒灯源的垂直位置，正值方向为上。","en_us":"Vertical position of the left-hand light, positive is up."},"slider":true}
#define OMNI_FLASHLIGHT_POS_L_Y -0.15 // [-1.5 -1.4 -1.3 -1.2 -1.1 -1.0 -0.9 -0.8 -0.7 -0.6 -0.5 -0.45 -0.4 -0.35 -0.3 -0.25 -0.2 -0.15 -0.1 -0.05 0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"水平位置-右持","en_us":"Horizontal offset - right"},"description":{"zh_cn":"右手手电筒灯源的水平位置，正值方向为右。","en_us":"Horizontal position of the right-hand light, positive is right."},"slider":true}
#define OMNI_FLASHLIGHT_POS_R_X 0.25 // [-1.0 -0.9 -0.8 -0.7 -0.6 -0.5 -0.45 -0.4 -0.35 -0.3 -0.25 -0.2 -0.15 -0.1 -0.05 0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"垂直位置-右持","en_us":"Vertical offset - right"},"description":{"zh_cn":"右手手电筒灯源的垂直位置，正值方向为上。","en_us":"Vertical position of the right-hand light, positive is up."},"slider":true}
#define OMNI_FLASHLIGHT_POS_R_Y -0.15 // [-1.5 -1.4 -1.3 -1.2 -1.1 -1.0 -0.9 -0.8 -0.7 -0.6 -0.5 -0.45 -0.4 -0.35 -0.3 -0.25 -0.2 -0.15 -0.1 -0.05 0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
#endif // 选项层结束
