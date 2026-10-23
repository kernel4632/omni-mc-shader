/*
阴影的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/shadow/shadow.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/shadow/shadow.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_SHADOW_SHADOW_INCLUDED
#define OMNI_EFFECT_SHADOW_SHADOW_INCLUDED
// @effect {"label":{"zh_cn":"阴影","en_us":"Shadows"}}
// @option {"label":{"zh_cn":"图投影偏差","en_us":"Shadow map bias"},"description":{"zh_cn":"阴影相机把边缘坐标向内收的程度；调大能减轻阴影边抖动，但远处阴影会略微缩小。","en_us":"How far shadow coordinates are pulled inward near the edge; larger hides edge wobble but slightly shrinks far shadows."},"slider":true}
#define OMNI_SHADOW_MAP_BIAS 0.9 // [0.0 0.1 0.7 0.75 0.8 0.85 0.9 0.92 0.94 0.96]
// @option {"label":{"zh_cn":"可变半影","en_us":"Variable penumbra"},"description":{"zh_cn":"按遮挡物远近自动调软阴影边缘：遮挡物离得远影子边更软，贴近时更锐。","en_us":"Widens shadow edges with the distance to the occluder, so far shadows are softer and near ones stay sharp."}}
#define OMNI_VARIABLE_PENUMBRA_SHADOWS 1 // [0 1]
// @option {"label":{"zh_cn":"基础模糊","en_us":"Shadow basic blur"},"description":{"zh_cn":"影子边缘的基础模糊量；调大整体更软，调小更锐。","en_us":"Base blur of the shadow edge; higher is softer overall."},"slider":true}
#define OMNI_SHADOW_BASIC_BLUR 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0]
// @option {"label":{"zh_cn":"半影采样数","en_us":"Penumbra samples"},"description":{"zh_cn":"可变半影每像素的采样次数；越大边缘越干净也越耗性能。","en_us":"Samples per pixel for the penumbra; higher is cleaner but costlier."}}
#define OMNI_VPS_QUALITY 16 // [4 8 12 16 24 32 48 64 96 128]
// @option {"label":{"zh_cn":"半影扩散","en_us":"Penumbra spread"},"description":{"zh_cn":"阴影边缘往外散开的宽度；调大半影更宽、影子更柔和。","en_us":"How wide the shadow edge spreads; larger gives a wider, softer penumbra."},"slider":true}
#define OMNI_VPS_SPREAD 0.1 // [0.02 0.03 0.05 0.07 0.1 0.15 0.2 0.3 0.5 0.7 1.0 1.5 2.0 3.0 5.0 7.0 10.0]
// @option {"label":{"zh_cn":"彩色半透明阴影","en_us":"Colored translucent shadows"},"description":{"zh_cn":"半透明方块用自身颜色给影子染色，例如有色玻璃投出同色的影子。","en_us":"Translucent blocks tint the shadow by their own color, such as stained glass casting a matching shadow."}}
#define OMNI_COLORED_SHADOWS 1 // [0 1]
// @option {"label":{"zh_cn":"屏幕阴影","en_us":"Screen space shadows"},"description":{"zh_cn":"补充阴影图覆盖不到的近处细节；关掉后植物等薄片可能出现漏光。","en_us":"Adds nearby detail the shadow map cannot cover; turning it off may cause light leaking through thin geometry."}}
#define OMNI_SCREEN_SPACE_SHADOWS
// @option {"label":{"zh_cn":"玩家关闭屏幕阴影","en_us":"Player screen shadows"},"description":{"zh_cn":"避免玩家自己身上出现屏幕空间阴影，减少第三人称下的错误暗块。","en_us":"Skips screen space shadows on the player to avoid wrong dark patches in third person."}}
//#define OMNI_DISABLE_PLAYER_SCREEN_SPACE_SHADOWS
// @option {"label":{"zh_cn":"透光采样数","en_us":"Subsurface samples"},"description":{"zh_cn":"叶片、草等透光材质每像素的散射采样次数；越大越干净也越耗性能。","en_us":"Scattering samples per pixel for translucent surfaces like leaves and grass; higher is cleaner but costlier."}}
#define OMNI_SSS_QUALITY 6 // [2 3 4 6 8 12 16 24 32]
// @option {"label":{"zh_cn":"透光亮度","en_us":"Translucency brightness"},"description":{"zh_cn":"阳光透过叶片、草时漏出的亮度；调大透光更明显。","en_us":"How bright sunlight glows through leaves and grass; larger makes the translucency stronger."},"slider":true}
#define OMNI_SSS_BRIGHTNESS 1.0 // [0.0 0.1 0.2 0.3 0.5 0.7 1.0 1.5 2.0 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 70.0 100.0]
// @option {"label":{"zh_cn":"焦散亮度","en_us":"Caustics brightness"},"description":{"zh_cn":"水面焦散花纹的整体亮度倍率，一为不变；来源 Eclipse `settings.glsl:999` 的 `WATER_CAUSTICS_BRIGHTNESS`。","en_us":"Overall brightness multiplier of the water caustics pattern; one is unchanged. From Eclipse `settings.glsl:999` `WATER_CAUSTICS_BRIGHTNESS`."},"slider":true}
#define OMNI_WATER_CAUSTICS_BRIGHTNESS 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0]
// @option {"label":{"zh_cn":"焦散对比","en_us":"Caustics power"},"description":{"zh_cn":"水面焦散花纹的对比指数，越大亮纹越集中、暗处越暗；一为不变。来源 Eclipse `settings.glsl:1000` 的 `WATER_CAUSTICS_POWER`。","en_us":"Contrast exponent of the water caustics pattern; larger concentrates the bright veins and darkens the rest; one is unchanged. From Eclipse `settings.glsl:1000` `WATER_CAUSTICS_POWER`."},"slider":true}
#define OMNI_WATER_CAUSTICS_POWER 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0 1.05 1.1 1.15 1.2 1.25 1.3 1.35 1.4 1.45 1.5 1.55 1.6 1.65 1.7 1.75 1.8 1.85 1.9 1.95 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0 3.2 3.4 3.6 3.8 4.0 4.5 5.0 6.0 7.0 8.0 9.0 10.0]
// @option {"label":{"zh_cn":"透光朝向","en_us":"Directional translucency"},"description":{"zh_cn":"让透过的光随观察角度变化，逆光看叶片时更亮。","en_us":"Makes the light through leaves vary with view angle, brighter when backlit."}}
#define OMNI_SSS_NORMAL 0 // [0 1]
// @option {"label":{"zh_cn":"远景透光（透光）","en_us":"Distant SSS"},"description":{"zh_cn":"让远景地形的叶片与雪像近景一样透光；关闭后远景叶片与雪不透光，影子更硬。默认开启，与原来一致。来源 Eclipse 的 DH_SUBSURFACE_SCATTERING。","en_us":"Lets distant leaves and snow pass light like nearby ones; when off they stop being translucent and shadows get harder. On by default. Ports Eclipse's DH_SUBSURFACE_SCATTERING."}}
#define OMNI_DH_SSS 1 // [0 1]
// @option {"label":{"zh_cn":"远景进阴影","en_us":"Distant terrain in shadows"},"description":{"zh_cn":"让远景地形也投进阴影图，远处山体才能挡住阳光。","en_us":"Casts distant terrain into the shadow map so far hills can block sunlight."}}
//#define OMNI_DH_SHADOW
// @option {"label":{"zh_cn":"远景阴影剔除","en_us":"Distant shadow culling"},"description":{"zh_cn":"剔除阴影图里被近处地形挡住、看不到的远景块，省性能；极端情况下可能出现阴影缺口。","en_us":"Culls distant chunks hidden behind near terrain in the shadow map to save cost; may rarely cut a shadow."}}
#define OMNI_DH_SHADOW_CULLING 1 // [0 1]
// @option {"label":{"zh_cn":"远景阴影伪影修复","en_us":"Distant shadow fix"},"description":{"zh_cn":"修正远景地形投出的颗粒状阴影伪影。","en_us":"Fixes grainy shadow artifacts cast by distant terrain."}}
#define OMNI_DH_SHADOW_FIX
// Iris 原生阴影分辨率常量必须直接使用字面量，菜单范围仍从这一行唯一读取。
// @option {"label":{"zh_cn":"分辨率","en_us":"Shadow resolution"},"description":{"zh_cn":"Iris 直接读取该原生常量并分配阴影纹理；越高影子越清晰也越占显存。","en_us":"Iris reads this native constant to allocate the shadow texture; higher is sharper and uses more VRAM."},"values":{"1024":{"zh_cn":"低","en_us":"Low"},"2048":{"zh_cn":"中","en_us":"Medium"},"4096":{"zh_cn":"高","en_us":"High"}}}
const int shadowMapResolution = 2048; // [1024 2048 4096 8192 16384 32768]
// Iris 原生阴影距离常量必须直接使用字面量，菜单范围仍从这一行唯一读取。
// @option {"label":{"zh_cn":"距离","en_us":"Shadow distance"},"description":{"zh_cn":"Iris 直接读取该原生常量并设置阴影覆盖范围，单位米。","en_us":"Iris reads this native constant to set the shadow range in meters."},"values":{"64.0":{"zh_cn":"近","en_us":"Near"},"128.0":{"zh_cn":"中","en_us":"Medium"},"192.0":{"zh_cn":"远","en_us":"Far"},"256.0":{"zh_cn":"极远","en_us":"Very far"}}}
const float shadowDistance = 192.0; // [64.0 96.0 128.0 192.0 256.0 384.0 512.0 768.0 1024.0 1536.0 2048.0]
#endif // 选项层结束
