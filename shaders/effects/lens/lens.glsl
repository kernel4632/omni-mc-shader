/*
效果文件 `effects/lens/lens.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/lens/lens.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_EFFECT_LENS_LENS_INCLUDED
#define OMNI_EFFECT_LENS_LENS_INCLUDED
// @effect {"label":{"zh_cn":"镜头","en_us":"Lens"}}
// @option {"label": {"zh_cn": "景深", "en_us": "Depth of field"}, "description": {"zh_cn": "让不在对焦平面上的物体模糊，模拟真实镜头。", "en_us": "Blurs objects away from the focal plane, like a real lens."}}
//#define OMNI_DOF
// @option {"label": {"zh_cn": "景深模糊量", "en_us": "Blur Amount"}, "slider": true, "description": {"zh_cn": "失焦处模糊的强度。", "en_us": "Strength of the out-of-focus blur."}}
#define OMNI_DOF_BLUR 0.01 // [0.001 0.0015 0.002 0.003 0.005 0.007 0.01 0.015 0.02 0.03 0.05 0.07 0.1 0.15 0.2 0.3 0.5 0.7 1.0 1.5 2.0 3.0 5.0]
// @option {"label": {"zh_cn": "焦距", "en_us": "Focal Length"}, "slider": true, "description": {"zh_cn": "镜头的焦距，单位毫米。越长失焦越强，像把镜头拉远拍特写；默认五十毫米是常见标准镜。来源 Eclipse `lib/settings.glsl:725` 的 `focal`。", "en_us": "Lens focal length in millimetres; longer blurs the out-of-focus areas more, like zooming in for a close-up. The default 50 mm is a common standard lens. From Eclipse `lib/settings.glsl:725` `focal`."}}
#define OMNI_DOF_FOCAL_LENGTH 50.0 // [8.0 12.0 16.0 20.0 24.0 28.0 35.0 40.0 50.0 60.0 70.0 85.0 100.0 135.0 150.0 200.0 250.0 300.0]
// @option {"label": {"zh_cn": "光圈", "en_us": "Aperture"}, "slider": true, "description": {"zh_cn": "光圈 f 值。数字越小光圈越大、失焦越糊，数字越大画面越锐利；默认 f/2.8 是常见大光圈。来源 Eclipse `lib/settings.glsl:726` 的 `fstop`。", "en_us": "Aperture f-number. A smaller number opens the aperture wider and blurs more; a larger number keeps more in focus. The default f/2.8 is a common fast aperture. From Eclipse `lib/settings.glsl:726` `fstop`."}}
#define OMNI_DOF_APERTURE 2.8 // [0.7 0.8 1.0 1.2 1.4 1.6 1.8 2.0 2.2 2.5 2.8 3.2 3.5 4.0 4.5 5.0 5.6 6.3 7.1 8.0 9.0 10.0 11.0 13.0 14.0 16.0 18.0 20.0 22.0]
// @option {"label": {"zh_cn": "景深采样数", "en_us": "Quality"}, "slider": true, "description": {"zh_cn": "散焦取样次数，越高越平滑也越慢。", "en_us": "Blur samples per pixel; higher is smoother and slower."}}
#define OMNI_DOF_QUALITY 10 // [5 7 10 15 20 30 50 70 100]
// @option {"label": {"zh_cn": "前景弥散范围采样数", "en_us": "CoC Spread Quality"}, "slider": true, "description": {"zh_cn": "统计前景弥散范围的搜索次数。", "en_us": "Search steps used to estimate foreground blur spread."}}
#define OMNI_DOF_COCSPREAD_QUALITY 10 // [5 7 10 15 20 30 50 70 100]
// @option {"label": {"zh_cn": "最大弥散半径", "en_us": "Max CoC Radius"}, "slider": true, "description": {"zh_cn": "单个像素最多模糊多少，限制景深开销。", "en_us": "Largest blur radius per pixel, capping the cost."}}
#define OMNI_DOF_MAX_COC 0.02 // [0.001 0.0015 0.002 0.003 0.005 0.007 0.01 0.015 0.02 0.03 0.05 0.07 0.1 0.15 0.2 0.3 0.5]
// @option {"label": {"zh_cn": "散景变形比", "en_us": "Anamorphic Ratio"}, "slider": true, "description": {"zh_cn": "横向拉伸失焦的光斑，模拟宽银幕变形镜头；默认一为正圆，不改画面。来源 Eclipse `lib/settings.glsl:720` 的 `DOF_ANAMORPHIC_RATIO`。", "en_us": "Stretches out-of-focus bokeh horizontally, like an anamorphic lens; the default 1 is a round bokeh and changes nothing. From Eclipse `lib/settings.glsl:720` `DOF_ANAMORPHIC_RATIO`."}}
#define OMNI_DOF_ANAMORPHIC_RATIO 1.0 // [0.3 0.6 1.0]
// @option {"label": {"zh_cn": "散景色散", "en_us": "Bokeh Dispersion"}, "slider": true, "description": {"zh_cn": "让失焦处的红蓝通道错开，产生彩色边缘；默认一为无色散，不改画面。来源 Eclipse `lib/settings.glsl:721` 的 `DOF_DISPERSION_MULT`。", "en_us": "Offsets the red and blue channels in out-of-focus areas for a colour fringe; the default 1 is neutral and changes nothing. From Eclipse `lib/settings.glsl:721` `DOF_DISPERSION_MULT`."}}
#define OMNI_DOF_DISPERSION_MULT 1.0 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.3 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.4 0.41 0.42 0.43 0.44 0.45 0.46 0.47 0.48 0.49 0.5 0.51 0.52 0.53 0.54 0.55 0.56 0.57 0.58 0.59 0.6 0.61 0.62 0.63 0.64 0.65 0.66 0.67 0.68 0.69 0.7 0.71 0.72 0.73 0.74 0.75 0.76 0.77 0.78 0.79 0.8 0.81 0.82 0.83 0.84 0.85 0.86 0.87 0.88 0.89 0.9 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99 1.0 1.01 1.02 1.03 1.04 1.05 1.06 1.07 1.08 1.09 1.1 1.11 1.12 1.13 1.14 1.15 1.16 1.17 1.18 1.19 1.2 1.21 1.22 1.23 1.24 1.25 1.26 1.27 1.28 1.29 1.3 1.31 1.32 1.33 1.34 1.35 1.36 1.37 1.38 1.39 1.4 1.41 1.42 1.43 1.44 1.45 1.46 1.47 1.48 1.49 1.5 1.51 1.52 1.53 1.54 1.55 1.56 1.57 1.58 1.59 1.6 1.61 1.62 1.63 1.64 1.65 1.66 1.67 1.68 1.69 1.7 1.71 1.72 1.73 1.74 1.75 1.76 1.77 1.78 1.79 1.8 1.81 1.82 1.83 1.84 1.85 1.86 1.87 1.88 1.89 1.9 1.91 1.92 1.93 1.94 1.95 1.96 1.97 1.98 1.99 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0 3.1 3.2 3.3 3.4 3.5 3.6 3.7 3.8 3.9 4.0 4.1 4.2 4.3 4.4 4.5 4.6 4.7 4.8 4.9 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0]
// @option {"label": {"zh_cn": "猫眼效应", "en_us": "Cat Eye"}, "description": {"zh_cn": "模拟镜头口径造成的画面边缘椭圆散景。", "en_us": "Edge-of-frame oval bokeh caused by the lens aperture."}}
#define OMNI_DOF_CATSEYE 0 // [0 1]
// @option {"label": {"zh_cn": "猫眼强度", "en_us": "Strength"}, "slider": true, "description": {"zh_cn": "猫眼裁剪的强度。", "en_us": "Strength of the cat-eye clipping."}}
#define OMNI_DOF_CATSEYE_STRENGTH 0.5 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label": {"zh_cn": "猫眼中点", "en_us": "Midpoint"}, "slider": true, "description": {"zh_cn": "从画面中心多远开始出现猫眼裁剪。", "en_us": "Distance from screen centre where the cat-eye starts."}}
#define OMNI_DOF_CATSEYE_MIDPOINT 0.3 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label": {"zh_cn": "对焦模式", "en_us": "Focus Mode"}, "description": {"zh_cn": "自动跟着屏幕中心变焦，或手动指定距离。", "en_us": "Auto focuses on the screen centre, or takes a fixed distance."}, "values": {"0": {"zh_cn": "自动", "en_us": "Auto"}, "1": {"zh_cn": "手动", "en_us": "Manual"}}}
#define OMNI_CAMERA_FOCUS_MODE 0 // [0 1]
// @option {"label": {"zh_cn": "手动对焦距离", "en_us": "Manual Focus Distance"}, "slider": true, "description": {"zh_cn": "手动模式的对焦距离，单位米。", "en_us": "Focus distance in manual mode, in metres."}}
#define OMNI_CAMERA_FOCAL_POINT 10.0 // [0.2 0.3 0.4 0.6 0.8 1.0 1.25 1.5 1.75 2.0 2.5 3.0 3.5 4.0 5.0 6.0 8.0 10.0 12.5 15.0 17.5 20.0 30.0 40.0 50.0 60.0 80.0 100.0 150.0 200.0 250.0 300.0 400.0 500.0 600.0 800.0 1000.0]
// @option {"label": {"zh_cn": "对焦深度平滑速度", "en_us": "Focus Smooth Speed"}, "slider": true, "description": {"zh_cn": "自动对焦切换焦点时过渡的快慢。", "en_us": "How fast auto focus moves to a new focal distance."}}
#define OMNI_DOF_DEPTH_SMOOTH_HALFLIFE 1.0 // [0.1 0.15 0.2 0.3 0.5 0.7 1.0 1.5 2.0 3.0 5.0 7.0 10.0]
// @option {"label": {"zh_cn": "对焦忽略手与粒子", "en_us": "Ignore Hand & Particles"}, "description": {"zh_cn": "屏幕中央是手或粒子时不改变对焦点，避免手持物品闪烁。", "en_us": "Keeps the focus when the centre is the hand or a particle."}}
#define OMNI_DOF_FOCUS_IGNORE_HAND_PARTICLE 1 // [0 1]
// @option {"label": {"zh_cn": "眩光", "en_us": "Lens Glare"}, "description": {"zh_cn": "太阳在画面中时沿光线方向产生细长眩光。", "en_us": "Draws a stretched glare from the sun highlight."}}
#define OMNI_LENS_GLARE 1 // [0 1]
// @option {"label":{"zh_cn":"光斑","en_us":"Lens Flare"},"description":{"zh_cn":"从太阳亮部生成一串鬼影与光环。","en_us":"Draws ghosts and a halo from the sun highlight."}}
#define OMNI_LENS_FLARE 0 // [0 1]
// @option {"label": {"zh_cn": "眩光亮度", "en_us": "Glare Brightness"}, "slider": true, "description": {"zh_cn": "眩光的强度。", "en_us": "Brightness of the glow glare."}}
#define OMNI_GLARE_BRIGHTNESS 1.0 // [0.1 0.2 0.3 0.5 0.7 1.0 1.5 2.0 3.0 5.0 7.0 10.0 15.0 20.0]
// @option {"label": {"zh_cn": "光斑亮度", "en_us": "Flare Brightness"}, "slider": true, "description": {"zh_cn": "鬼影与光环的强度。", "en_us": "Brightness of the ghosts and halo."}}
#define OMNI_FLARE_BRIGHTNESS 1.0 // [0.1 0.2 0.3 0.5 0.7 1.0 1.5 2.0 3.0 5.0 7.0 10.0 15.0 20.0]
// @option {"label": {"zh_cn": "按阴影遮挡减弱眩光", "en_us": "Shadow Based Glare"}, "description": {"zh_cn": "太阳被阴影挡住时让眩光一并减弱。", "en_us": "Fades the glare when the sun is shadowed."}}
//#define OMNI_GLARE_FLARE_SHADOWBASED
// @option {"label": {"zh_cn": "相机动态模糊", "en_us": "Motion Blur"}, "description": {"zh_cn": "相机移动时画面沿运动方向拖出残影。", "en_us": "Smears the image along camera motion."}}
#define OMNI_MOTION_BLUR 0 // [0 1]
// @option {"label": {"zh_cn": "动态模糊抖动", "en_us": "Motion Blur Dither"}, "description": {"zh_cn": "给动态模糊采样加抖动，减少采样不足产生的条纹。", "en_us": "Dithers the motion blur samples to reduce banding."}}
#define OMNI_MOTION_BLUR_DITHER 1 // [0 1]
// @option {"label": {"zh_cn": "动态模糊采样数", "en_us": "Motion Blur Quality"}, "slider": true, "description": {"zh_cn": "沿运动方向取多少个样本，越高越顺滑。", "en_us": "Samples along the motion direction; higher is smoother."}}
#define OMNI_MOTION_BLUR_QUALITY 3 // [2 3 5 10 20 30 50 100]
// @option {"label": {"zh_cn": "快门角度", "en_us": "Shutter Angle"}, "slider": true, "description": {"zh_cn": "快门张开的角度，越大拖影越长。", "en_us": "Shutter opening angle; larger means longer trails."}}
#define OMNI_MOTION_BLUR_SHUTTER_ANGLE 135.0 // [45.0 90.0 135.0 180.0 270.0 360.0]
// @option {"label": {"zh_cn": "暗角", "en_us": "Vignette"}, "description": {"zh_cn": "画面四角变暗，模拟镜头边缘失光。", "en_us": "Darkens the corners, like lens falloff."}}
#define OMNI_VIGNETTE 1 // [0 1]
// @option {"label": {"zh_cn": "暗角衰减", "en_us": "Falloff"}, "slider": true, "description": {"zh_cn": "暗角的强度，越大越暗。", "en_us": "Strength of the vignette."}}
#define OMNI_VIGNETTE_FALLOFF 0.4 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label": {"zh_cn": "暗角圆度", "en_us": "Roundness"}, "slider": true, "description": {"zh_cn": "零为椭圆暗角，一为圆形暗角。", "en_us": "Zero is an oval vignette, one is circular."}}
#define OMNI_VIGNETTE_ROUNDNESS 0.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label": {"zh_cn": "潜行暗角", "en_us": "Sneaking Vignette"}, "description": {"zh_cn": "潜行时画面下边缘出现额外暗角。", "en_us": "Adds a bottom-edge vignette while sneaking."}}
#define OMNI_SNEAKING_VIGNETTE 0 // [0 1]

// --- 效果实现：宿主输入、参数换算与阶段入口 ---
/*
镜头成像：景深、弥散范围统计、镜头眩光与光斑、相机动态模糊、暗角，合成成一套相机成像效果。
来源：景深照 iterationT `Lib/IndividualFounctions/DOF.glsl` 一比一移植；
  景深的散景变形与色散照 Eclipse `lib/settings.glsl:720-721` 的 `DOF_ANAMORPHIC_RATIO`、`DOF_DISPERSION_MULT`
  与 `dimensions/composite11.fsh:251-258` 的采样方式移植，两项默认值一表示不变形、不色散，默认画面不变；
  景深的焦距与光圈照 Eclipse `lib/settings.glsl:725-727` 的 `focal`、`fstop` 与 `aperture = focal/fstop`
  换算相对模糊倍数，默认五十毫米、f/2.8 正好等于一，不改动原来由 `OMNI_DOF_BLUR` 决定的模糊量；
  眩光与光斑照 iterationT `Lib/IndividualFounctions/LensGlareFlare.glsl` 一比一移植；
  相机速度与动态模糊照 iterationT `Lib/IndividualFounctions/MotionBlur.glsl` 的模糊部分一比一移植；
  暗角照 iterationT `Lib/Programs/Final.glsl` 的 `Vignette` 一比一移植。
  曝光统计（平均亮度与 `AE_*`）不属于本文件，按合同放在 `effects/color/color.glsl`。
调用位置：
  合成五号片元在景深开启时调用 `CoCSpread` 取弥散范围，并调用 `LensFlare` 写镜头光斑到三号画面；
  合成六号片元调用 `DepthOfField` 做景深；
  合成八号片元调用 `MotionBlur` 做相机动态模糊；
  合成十四号片元调用 `Vignette` 画暗角。
本文件的相机速度函数叫 `MotionBlurCameraVelocity`：它只按相机位移算屏幕位移，不回填深度。
  同名用途在 `effects/clarity/antialiasing.glsl` 是 `TaaCameraVelocity`、在 `effects/lighting/ambient.glsl` 是
  `GiCameraVelocity`，三份实现不同，按 iterationT 原程序各留一份，名字体现用途以区分。
可复制示例：
  `compositeOutput1 = DepthOfField();`
  `float spread = CoCSpread();`
  `color += CurveToLinear(texelFetch(colortex3, texelCoord, 0).rgb) * eyeBrightnessSmoothCurved;`
  `color *= Vignette(texCoord, OMNI_VIGNETTE_FALLOFF, OMNI_VIGNETTE_ROUNDNESS);`
调用前提（iterationT 原样保留）：
  调用方必须先声明 `texCoord`、`texelCoord` 全局量，并让材质编号 `MATID_*` 可见；
  `LensFlare` 还要用到从合成顶点程序插值进来的 `sunCoord`、`colorSunlight`、`sunVisibility`；
  `CoCSpread`、`DepthOfField`、`MotionBlur` 里的随机数按 `OMNI_TAA` 决定是否随时间变化，
  所以本文件先引入定义该选项的 `effects/clarity/antialiasing.glsl`；`LensFlare` 用到 `OMNI_VFOG_DENSITY`，
  由 `effects/fog/fog.glsl` 提供。
设计原因与取舍：
  这些效果共用同一套屏幕元数据与坐标约定，放在一个文件里，读取同一份深度和颜色；
  每个效果各自成函数，关闭时用预处理器在编译期直接去掉对应循环，不为关闭的功能付出逐像素开销。
    本文件按算法拆到同目录：景深在 `dof.glsl`，眩光与光斑在 `glare.glsl`，相机动态模糊在 `motion_blur.glsl`；暗角只有几行仍留在本文件；引入顺序与拆分前逐字一致。
*/

// 加载器输入、共享数学、时间噪声先引入；坐标换算依赖本文件先定义的 `OMNI_TAA`，所以放在选项之后。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
// 暗角曲线放在通用库，这里只传入画面纵横比与选项。
#include "/omni-gfx/post.glsl"
#include "/effects/clarity/antialiasing.glsl"
#include "/common/noise.glsl"

// 景深：弥散圆、散焦范围与散焦合成。
#include "/effects/lens/dof.glsl"
// 镜头眩光与光斑。
#include "/effects/lens/glare.glsl"
// 相机动态模糊。
#include "/effects/lens/motion_blur.glsl"
// --- 暗角 ---
// 按到画面中心的距离把四角压暗；`falloff` 是强度，`roundness` 在椭圆与圆形之间插值。
float Vignette(vec2 coord, const float falloff, const float roundness){
	return ogxVignette(coord, falloff, roundness, aspectRatio); // 画面纵横比由效果层传入。
}
#endif // OMNI_EFFECT_LENS_LENS_INCLUDED
