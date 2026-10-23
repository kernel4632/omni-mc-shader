/*
环境光与遮蔽的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/lighting/ambient.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/lighting/ambient.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_LIGHTING_AMBIENT_INCLUDED
#define OMNI_EFFECT_LIGHTING_AMBIENT_INCLUDED
// @effect {"label":{"zh_cn":"环境光与遮蔽","en_us":"GI & AO"}}
// @option {"label":{"zh_cn":"全局光反射阴影图","en_us":"GI RSM"},"description":{"zh_cn":"用阴影图里可见的表面做一次屏幕外反弹，给阴影补光。","en_us":"Bounces light from surfaces visible in the shadow map to fill in shadows."}}
#define OMNI_GI_RSM 1 // [0 1]
// @option {"label":{"zh_cn":"全局光质量","en_us":"GI Quality"},"description":{"zh_cn":"每个像素的反弹采样次数，越高越干净也越慢。","en_us":"Bounce samples per pixel; higher is cleaner and slower."},"slider":true}
#define OMNI_GI_QUALITY 16 // [4 8 12 16 24 32 48 64 96 128]
// @option {"label":{"zh_cn":"全局光半径","en_us":"GI Radius"},"description":{"zh_cn":"反弹搜索的半径，越大补光越广。","en_us":"Search radius of the bounce; larger spreads more light."},"slider":true}
#define OMNI_GI_RADIUS 7.0 // [1.0 1.5 2.0 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 70.0 100.0]
// @option {"label":{"zh_cn":"全局光亮度","en_us":"GI Brightness"},"description":{"zh_cn":"反弹补光的整体亮度。","en_us":"Overall brightness of the bounce light."},"slider":true}
#define OMNI_GI_BRIGHTNESS 1.0 // [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.6 1.8 2.0 2.5 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 70.0 100.0]
// @option {"label":{"zh_cn":"全局光渲染分辨率","en_us":"GI Render Resolution"},"description":{"zh_cn":"全局光在多少分辨率上算，半分辨率更省。","en_us":"Resolution the GI is computed at; half is cheaper."},"values":{"0.25":{"zh_cn":"四分之一","en_us":"Quarter"},"0.5":{"zh_cn":"一半","en_us":"Half"}}}
#define OMNI_GI_RENDER_RESOLUTION 0.5 // [0.25 0.5]
// @option {"label":{"zh_cn":"全局光衰减","en_us":"GI Falloff"},"description":{"zh_cn":"反弹随距离衰减的指数，越大越只影响近处。","en_us":"Distance falloff exponent of the bounce; higher keeps it near."},"slider":true}
#define OMNI_GI_FALLOFF 1.1 // [1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label":{"zh_cn":"全局光天光衰减","en_us":"GI Skylight Falloff"},"description":{"zh_cn":"反弹随天空光等级衰减，避免洞穴里也被补到光。","en_us":"Fades the bounce with skylight so caves are not lit."}}
#define OMNI_GI_SKYLIGHT_FALLOFF
// @option {"label":{"zh_cn":"关闭手部全局光","en_us":"Disable Hand GI"},"description":{"zh_cn":"手不接收屏幕外的反弹补光。","en_us":"Keeps the hand from receiving off-screen bounce light."}}
//#define OMNI_DISABLE_HAND_GI
// @option {"label":{"zh_cn":"关闭手部全局光速度","en_us":"Disable Hand GI Velocity"},"description":{"zh_cn":"手不参与全局光的历史重投影，减少手的拖影。","en_us":"Excludes the hand from GI history reprojection to reduce smearing."}}
#define OMNI_DISABLE_HAND_GI_VELOCITY 0 // [0 1]
// @option {"label":{"zh_cn":"关闭玩家全局光","en_us":"Disable Player GI"},"description":{"zh_cn":"玩家角色不接收屏幕外的反弹补光。","en_us":"Keeps the player from receiving off-screen bounce light."}}
//#define OMNI_DISABLE_PLAYER_GI
// @option {"label":{"zh_cn":"关闭玩家全局光速度","en_us":"Disable Player GI Velocity"},"description":{"zh_cn":"玩家不参与全局光的历史重投影。","en_us":"Excludes the player from GI history reprojection."}}
#define OMNI_DISABLE_PLAYER_GI_VELOCITY 0 // [0 1]
// @option {"label":{"zh_cn":"地平线暗部","en_us":"GTAO"},"description":{"zh_cn":"地面真相环境遮蔽，墙角缝隙变暗。","en_us":"Ground-truth ambient occlusion; darkens corners and creases."}}
#define OMNI_GTAO
// @option {"label":{"zh_cn":"暗部质量","en_us":"GTAO Quality"},"description":{"zh_cn":"环绕视线的切片数，越高越稳也越慢。","en_us":"Slices around the view; higher is steadier and slower."},"slider":true}
#define OMNI_GTAO_QUALITY 3 // [1 2 3 4 5 6 8 10 15 20]
// @option {"label":{"zh_cn":"暗部切片质量","en_us":"GTAO Slice Quality"},"description":{"zh_cn":"每个切片的搜索步数。","en_us":"Search steps per slice."},"slider":true}
#define OMNI_GTAO_SLICE_QUALITY 3 // [1 2 3 4 5 6 8 10 15 20]
// @option {"label":{"zh_cn":"暗部半径模式","en_us":"GTAO Radius Mode"},"description":{"zh_cn":"零为世界半径，一为屏幕半径。","en_us":"Zero uses world radius, one uses screen radius."},"values":{"0":{"zh_cn":"世界","en_us":"World"},"1":{"zh_cn":"屏幕","en_us":"Screen"}}}
#define OMNI_GTAO_RADIUS_MODE 0 // [0 1]
// @option {"label":{"zh_cn":"暗部世界半径","en_us":"GTAO World Radius"},"description":{"zh_cn":"世界半径模式下的取样半径，单位方块。","en_us":"Sample radius in world-radius mode, in blocks."},"slider":true}
#define OMNI_GTAO_WORLD_RADIUS 2.0 // [0.5 0.7 1.0 1.5 2.0 3.0 5.0 7.0 10.0 15.0 20.0]
// @option {"label":{"zh_cn":"暗部屏幕半径","en_us":"GTAO Screen Radius"},"description":{"zh_cn":"屏幕半径模式下的取样半径，单位屏幕比例。","en_us":"Sample radius in screen-radius mode, in screen fraction."},"slider":true}
#define OMNI_GTAO_SCREEN_RADIUS 0.05 // [0.001 0.0015 0.002 0.003 0.005 0.007 0.01 0.015 0.02 0.03 0.05 0.07 0.1 0.15 0.2 0.3 0.5]
// @option {"label":{"zh_cn":"暗部最大半径","en_us":"GTAO Max Radius"},"description":{"zh_cn":"屏幕半径上限，避免近处取样范围过大。","en_us":"Cap on the screen radius so near geometry does not over-sample."},"slider":true}
#define OMNI_GTAO_MAX_RADIUS 0.1 // [0.01 0.015 0.02 0.03 0.05 0.07 0.1 0.15 0.2 0.3 0.5]
// @option {"label":{"zh_cn":"暗部衰减起点","en_us":"GTAO Falloff Start"},"description":{"zh_cn":"远处样本开始衰减的位置比例。","en_us":"Fraction at which far samples start to fade."},"slider":true}
#define OMNI_GTAO_FALLOFF_START 0.7 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"暗部强度","en_us":"GTAO Strength"},"description":{"zh_cn":"遮蔽压暗的强度，取零等于关闭。","en_us":"Darkening strength of the AO; zero disables it."},"slider":true}
#define OMNI_GTAO_STRENGTH 0.95 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.525 0.55 0.575 0.6 0.625 0.65 0.675 0.7 0.725 0.75 0.775 0.8 0.85 0.9 0.95 1.0]
// @option {"label":{"zh_cn":"暗部多弹射","en_us":"GTAO Multibounce"},"description":{"zh_cn":"按表面底色给遮蔽做一次多弹射补偿，暗部不会压死。","en_us":"Multi-bounce correction using albedo so dark areas do not crush."}}
#define OMNI_GTAO_MULTIBOUNCE
// @option {"label":{"zh_cn":"远景暗部","en_us":"Distant AO"},"description":{"zh_cn":"让远景地形参与地平线遮蔽与全局光；关闭后远景不接收遮蔽，近景也不会被远景挡住。默认开启，与原来一致。来源 Eclipse 的 DH_AMBIENT_OCCLUSION。","en_us":"Lets distant terrain take part in ground-truth AO and GI; when off, distant chunks get no occlusion and nearby pixels are not occluded by distant geometry. On by default. Ports Eclipse's DH_AMBIENT_OCCLUSION."}}
#define OMNI_DH_AO 1 // [0 1]
#endif // 选项层结束
