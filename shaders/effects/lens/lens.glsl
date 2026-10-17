/*
镜头成像：景深、弥散范围统计、镜头眩光与光斑、相机动态模糊、暗角，合成成一套相机成像效果。
来源：景深照 iterationT `Lib/IndividualFounctions/DOF.glsl` 一比一移植；
  景深的散景变形与色散照 Eclipse `lib/settings.glsl:720-721` 的 `DOF_ANAMORPHIC_RATIO`、`DOF_DISPERSION_MULT`
  与 `dimensions/composite11.fsh:251-258` 的采样方式移植，两项默认值一表示不变形、不色散，默认画面不变；
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
*/
#ifndef OMNI_LENS_INCLUDED // 只引入一次，避免选项、内部常数与函数重复定义。
#define OMNI_LENS_INCLUDED // 置上标记。
// @effect {"label":{"zh_cn":"镜头","en_us":"Lens"}}
// @option {"label": {"zh_cn": "景深", "en_us": "Depth of field"}, "description": {"zh_cn": "让不在对焦平面上的物体模糊，模拟真实镜头。", "en_us": "Blurs objects away from the focal plane, like a real lens."}}
//#define OMNI_DOF
// @option {"label": {"zh_cn": "景深模糊量", "en_us": "Blur Amount"}, "slider": true, "description": {"zh_cn": "失焦处模糊的强度。", "en_us": "Strength of the out-of-focus blur."}}
#define OMNI_DOF_BLUR 0.01 // [0.001 0.0015 0.002 0.003 0.005 0.007 0.01 0.015 0.02 0.03 0.05 0.07 0.1 0.15 0.2 0.3 0.5 0.7 1.0 1.5 2.0 3.0 5.0]
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
//#define OMNI_DOF_CATSEYE
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
#define OMNI_DOF_FOCUS_IGNORE_HAND_PARTICLE
// @option {"label": {"zh_cn": "眩光", "en_us": "Lens Glare"}, "description": {"zh_cn": "太阳在画面中时沿光线方向产生细长眩光。", "en_us": "Draws a stretched glare from the sun highlight."}}
#define OMNI_LENS_GLARE
// @option {"label": {"zh_cn": "镜头光斑", "en_us": "Lens Flare"}, "description": {"zh_cn": "从太阳亮部生成一串鬼影与光环。", "en_us": "Draws ghosts and a halo from the sun highlight."}}
//#define OMNI_LENS_FLARE
// @option {"label": {"zh_cn": "眩光亮度", "en_us": "Glare Brightness"}, "slider": true, "description": {"zh_cn": "眩光的强度。", "en_us": "Brightness of the glow glare."}}
#define OMNI_GLARE_BRIGHTNESS 1.0 // [0.1 0.2 0.3 0.5 0.7 1.0 1.5 2.0 3.0 5.0 7.0 10.0 15.0 20.0]
// @option {"label": {"zh_cn": "光斑亮度", "en_us": "Flare Brightness"}, "slider": true, "description": {"zh_cn": "鬼影与光环的强度。", "en_us": "Brightness of the ghosts and halo."}}
#define OMNI_FLARE_BRIGHTNESS 1.0 // [0.1 0.2 0.3 0.5 0.7 1.0 1.5 2.0 3.0 5.0 7.0 10.0 15.0 20.0]
// @option {"label": {"zh_cn": "按阴影遮挡减弱眩光", "en_us": "Shadow Based Glare"}, "description": {"zh_cn": "太阳被阴影挡住时让眩光一并减弱。", "en_us": "Fades the glare when the sun is shadowed."}}
//#define OMNI_GLARE_FLARE_SHADOWBASED
// @option {"label": {"zh_cn": "相机动态模糊", "en_us": "Motion Blur"}, "description": {"zh_cn": "相机移动时画面沿运动方向拖出残影。", "en_us": "Smears the image along camera motion."}}
#define OMNI_MOTION_BLUR
// @option {"label": {"zh_cn": "动态模糊抖动", "en_us": "Motion Blur Dither"}, "description": {"zh_cn": "给动态模糊采样加抖动，减少采样不足产生的条纹。", "en_us": "Dithers the motion blur samples to reduce banding."}}
#define OMNI_MOTION_BLUR_DITHER
// @option {"label": {"zh_cn": "动态模糊采样数", "en_us": "Motion Blur Quality"}, "slider": true, "description": {"zh_cn": "沿运动方向取多少个样本，越高越顺滑。", "en_us": "Samples along the motion direction; higher is smoother."}}
#define OMNI_MOTION_BLUR_QUALITY 3 // [2 3 5 10 20 30 50 100]
// @option {"label": {"zh_cn": "快门角度", "en_us": "Shutter Angle"}, "slider": true, "description": {"zh_cn": "快门张开的角度，越大拖影越长。", "en_us": "Shutter opening angle; larger means longer trails."}}
#define OMNI_MOTION_BLUR_SHUTTER_ANGLE 135.0 // [45.0 90.0 135.0 180.0 270.0 360.0]
// @option {"label": {"zh_cn": "暗角", "en_us": "Vignette"}, "description": {"zh_cn": "画面四角变暗，模拟镜头边缘失光。", "en_us": "Darkens the corners, like lens falloff."}}
#define OMNI_VIGNETTE
// @option {"label": {"zh_cn": "暗角衰减", "en_us": "Falloff"}, "slider": true, "description": {"zh_cn": "暗角的强度，越大越暗。", "en_us": "Strength of the vignette."}}
#define OMNI_VIGNETTE_FALLOFF 0.4 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label": {"zh_cn": "暗角圆度", "en_us": "Roundness"}, "slider": true, "description": {"zh_cn": "零为椭圆暗角，一为圆形暗角。", "en_us": "Zero is an oval vignette, one is circular."}}
#define OMNI_VIGNETTE_ROUNDNESS 0.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label": {"zh_cn": "潜行暗角", "en_us": "Sneaking Vignette"}, "description": {"zh_cn": "潜行时画面下边缘出现额外暗角。", "en_us": "Adds a bottom-edge vignette while sneaking."}}
//#define OMNI_SNEAKING_VIGNETTE

// 加载器输入、共享数学、时间噪声先引入；坐标换算依赖本文件先定义的 `OMNI_TAA`，所以放在选项之后。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
#include "/effects/clarity/antialiasing.glsl"
#include "/common/noise.glsl"

// --- 景深：弥散圆半径与深度 ---
// 按薄透镜公式估算一个点的弥散圆半径：离对焦平面越远，弥散越大。
// `f` 是对焦距离，`d` 是该点距离，`a` 是口径系数；三者单位一致时结果就是像素半径。
float CalculateCoCRadius(float f, float d, float a){
	return abs(a * (d - f) / (d * f)); // 薄透镜近似。
}

// 读某个坐标的米制深度；远景像素改用远景深度，并给一个近处下限避免紧贴相机时数值失控。
float GetLinearDepth(vec2 coord){
	float depth = textureLod(depthtex0, coord, 0.0).x; // 读含半透明的深度。
	#ifdef DISTANT_HORIZONS // 有远景模组时判断是否远景像素。
		if (depth == 1.0){ // 深度为一说明近处没有几何。
			depth = textureLod(dhDepthTex0, coord, 0.0).x; // 改用远景深度。
			depth = saturate(ScreenDepth_From_DHScreenDepth(depth)); // 换到近景深度尺度。
		}
	#endif
	depth = max(depth, 0.875); // 近处下限，避免对焦距离趋近零时弥散爆炸。
	return LinearDepth_From_ScreenDepth(depth); // 换成米制距离。
}

// 取对焦距离：自动模式读屏幕中心的历史深度并平滑，手动模式直接用选项。
float GetFocus(){
	#if OMNI_CAMERA_FOCUS_MODE == 0 // 自动对焦。
		float focus = LinearDepth_From_ScreenDepth(texelFetch(colortex2, ivec2(60, screenSize.y - 1.0), 0).a * 0.125 + 0.875); // 读顶行统计像素里保存的对焦深度并解码。
	#else // 手动对焦。
		float focus = OMNI_CAMERA_FOCAL_POINT; // 直接用选项给的距离。
	#endif
	return focus; // 返回对焦距离。
}

// --- 景深：前景弥散范围统计 ---
// 在螺旋上撒一圈样本，找出附近比当前点更近、弥散更大的点，把它们的弥散并进来。
// 为什么需要它：一个像素要被足够大的前景散焦覆盖，否则近处物体边缘会显得又硬又细。
float CoCSpread(){
	float cocRadiusfactor = OMNI_DOF_BLUR * gbufferProjection[1][1]; // 口径系数，投影矩阵的纵向缩放乘以模糊量。
	const float maxCoc = OMNI_DOF_MAX_COC; // 最大弥散半径。
	const float rMaxCoc = 1.0 / maxCoc; // 半径倒数，用于归一化。
	float rAspectRatio = 1.0 / aspectRatio; // 宽高比倒数，让椭圆散景在像素上是圆的。
	#ifdef OMNI_TAA // 开时间抗锯齿时用随时间变化的噪声，避免固定图案。
		vec2 noise = BlueNoiseTemporal(); // 每帧变化的蓝噪声。
	#else // 关闭时用固定蓝噪声。
		vec2 noise = BlueNoise(); // 固定蓝噪声。
	#endif
	float currDepth = GetLinearDepth(texCoord); // 当前点的米制深度。
	float focus = GetFocus(); // 对焦距离。
	float currCoc = CalculateCoCRadius(focus, currDepth, cocRadiusfactor); // 当前点的弥散半径。
	float startRadius = currCoc * rMaxCoc; // 当前弥散占最大值的比例。
	startRadius *= startRadius; // 平方，让搜索从中心附近开始。
	float spreadCoc = currCoc; // 弥散范围初值为当前点的弥散。
	const float steps = OMNI_DOF_COCSPREAD_QUALITY; // 搜索步数。
	const float rSteps = 1.0 / steps; // 步数倒数。
	const mat2 rotMat = mat2(cos(goldenAngle), sin(goldenAngle), -sin(goldenAngle), cos(goldenAngle)); // 黄金角旋转矩阵。
	float angle = noise.x * TAU; // 起始角。
	vec2 rot = vec2(cos(angle), sin(angle)); // 起始方向。
	for (float i = 0.0; i < steps; i++){ // 螺旋逐点搜索。
		rot *= rotMat; // 每步旋转一点。
		float sampleRadius = sqrt(startRadius + (i + noise.y) * (1.0 - startRadius) * rSteps) * maxCoc; // 这个样本的半径。
		vec2 sampleCoordOffset = rot * sampleRadius; // 屏幕偏移。
		sampleCoordOffset.x *= rAspectRatio; // 按宽高比修正成圆。
		vec2 sampleCoord = texCoord + sampleCoordOffset; // 样本坐标。
		float sampleDepth = GetLinearDepth(sampleCoord); // 样本深度。
		float sampleCoC = CalculateCoCRadius(focus, sampleDepth, cocRadiusfactor); // 样本弥散。
		if (sampleCoC >= sampleRadius && sampleDepth <= currDepth){ // 只有样本弥散足够大且比当前点更近才并进来。
			spreadCoc = max(spreadCoc, sampleCoC); // 扩大弥散范围。
		}
	}
	spreadCoc = min(spreadCoc, maxCoc) * rMaxCoc; // 夹到最大值并归一化。
	return spreadCoc; // 返回归一化的弥散范围。
}

// --- 景深：散焦合成 ---
// 按弥散半径在螺旋上取样，只让"更近且弥散够大"的样本散到当前像素上，得到背景向近处的柔和过渡。
// 这样做能避免远处背景糊到近处清晰物体上，也能让近处前景盖住后面的背景。

// 下界散焦要把深度也一起带出画面：把这一样本的深度按它属于当前点自己、还是散焦进来，累加进对应累加器。
// 主世界与末地不需要这份深度，函数体只在为下界编译时生效，调用点也随宏去掉，不产生额外开销。
// 输入是“属于当前点自己”“散焦进来”两个判断、样本深度、散焦权重与两个累加器；就地更新两个累加器。
void AccumulateDOFDepth(bool isSelfSample, bool isBlurredSample, float sampleDepth, float sampleWeight, inout float selfDepth, inout float blendedDepth){
	#ifdef OMNI_NETHER
		if (isSelfSample) selfDepth += sampleDepth; // 属于当前点自己的样本累加自贡献深度。
		else if (isBlurredSample) blendedDepth += sampleDepth * sampleWeight; // 散焦进来的样本按权重累加深度。
	#endif
}

vec4 DepthOfField(){
	float cocRadiusfactor = OMNI_DOF_BLUR * gbufferProjection[1][1]; // 口径系数。
	float minCoc = 0.5641895835 * pixelSize.y; // 一个像素大小的最小弥散，避免零半径时除零。
	const float maxCoc = OMNI_DOF_MAX_COC; // 最大弥散半径。
	float rAspectRatio = 1.0 / aspectRatio; // 宽高比倒数。
	#ifdef OMNI_TAA // 时间噪声选择同上面。
		vec2 noise = BlueNoiseTemporal(); // 每帧变化的蓝噪声。
	#else
		vec2 noise = BlueNoise(); // 固定蓝噪声。
	#endif
	float currDepth = GetLinearDepth(texCoord); // 当前点深度。
	float focus = GetFocus(); // 对焦距离。
	float currCoc = CalculateCoCRadius(focus, currDepth, cocRadiusfactor); // 当前点弥散。
	currCoc = clamp(currCoc, minCoc, maxCoc); // 夹在最小与最大之间。
	vec4 currData = textureLod(colortex1, texCoord, 0.0); // 读当前点的曲线编码颜色与弥散范围。
	float spreadCoc = currData.a * maxCoc; // 把存下来的弥散范围还原成半径。
	float centerWeight = spreadCoc * spreadCoc - spreadCoc + 1.0; // 中心权重多项式。
	centerWeight = mix(centerWeight, 1e-20, pow(currCoc / spreadCoc, 4.0)); // 当前点自己很清晰时把它自己压到极小。
	#ifdef OMNI_DOF_CATSEYE // 猫眼效应：把散焦区域在画面边缘裁成椭圆。
		vec2 catsEyeOffset = (texCoord) * 2.0 - 1.0; // 从中心指向当前点。
		catsEyeOffset.x *= aspectRatio; // 按宽高比修正成圆。
		float catsEyeDist = length(catsEyeOffset); // 到中心的距离。
		catsEyeDist = max(catsEyeDist - OMNI_DOF_CATSEYE_MIDPOINT, 0.0); // 超过中点才开始裁剪。
		catsEyeDist *= spreadCoc * OMNI_DOF_CATSEYE_STRENGTH; // 按弥散与强度缩放。
		catsEyeOffset = normalize(catsEyeOffset) * catsEyeDist; // 得到裁剪半径。
	#endif
	vec3 dof = vec3(0.0); // 散焦进来的颜色累加。
	float weights = 0.0; // 样本权重累加。
	vec3 selfColor = CurveToLinear(currData.rgb) * 1e-20; // 当前点自贡献初值极小。
	float selfSamples = 1e-20; // 当前点自计入的样本数初值极小。
	float selfWeights = 0.0; // 被拒绝样本在中心上的权重累加。
	#ifdef OMNI_NETHER // 下界还要带出散焦后的深度。
		float blendedDepth = 0.0; // 散焦后的深度累加。
		float selfDepth = currDepth * 1e-20; // 当前点自计入深度初值极小。
	#endif
	const float steps = OMNI_DOF_QUALITY; // 采样步数。
	const float rSteps = 1.0 / steps; // 步数倒数。
	const float firstStepRadius = sqrt(rSteps); // 首个样本半径，原程序保留。
	const mat2 rotMat = mat2(cos(goldenAngle), sin(goldenAngle), -sin(goldenAngle), cos(goldenAngle)); // 黄金角旋转矩阵。
	float angle = noise.x * TAU; // 起始角。
	vec2 rot = vec2(cos(angle), sin(angle)); // 起始方向。
	for (float i = 0.0; i < steps; i++){ // 螺旋采样。
		rot *= rotMat; // 每步旋转一点。
		float sampleRadius = sqrt((i + noise.y) * rSteps) * spreadCoc; // 样本半径。
		vec2 sampleCoordOffset = rot * sampleRadius; // 屏幕偏移。
		#ifdef OMNI_DOF_CATSEYE // 猫眼裁剪：偏移超出裁剪半径就跳过。
			if (distance(catsEyeOffset, sampleCoordOffset) > spreadCoc) continue; // 超出就不采。
		#endif
		sampleCoordOffset.x *= rAspectRatio * OMNI_DOF_ANAMORPHIC_RATIO; // 按宽高比修正后再按变形比横向拉伸；变形比为一表示不变形。
		vec2 sampleCoord = texCoord + sampleCoordOffset; // 样本坐标。
		float sampleDepth =  GetLinearDepth(sampleCoord); // 样本深度。
		float sampleCoC = CalculateCoCRadius(focus, sampleDepth, cocRadiusfactor); // 样本弥散。
		sampleCoC = clamp(sampleCoC, minCoc, maxCoc); // 夹到范围。
		vec3 sampleColor; // 样本线性颜色，下面按是否做色散分两条路取。
		if (OMNI_DOF_DISPERSION_MULT != 1.0){ // 色散开启时：红蓝通道沿到画面中心的方向错开，绿通道不动。
			// 为什么减一：让默认值一表示「不错开」，与原程序默认一致，保证默认画面不变；
			// 偏移量随样本半径与到中心的距离增大，越靠边、越失焦的像素色边越明显。
			vec2 dispersionOffset = (texCoord - 0.5) * sampleRadius * (OMNI_DOF_DISPERSION_MULT - 1.0);
			sampleColor.r = CurveToLinear(textureLod(colortex1, sampleCoord + dispersionOffset, 0.0).r); // 红通道向外错开。
			sampleColor.g = CurveToLinear(textureLod(colortex1, sampleCoord, 0.0).g); // 绿通道不动。
			sampleColor.b = CurveToLinear(textureLod(colortex1, sampleCoord - dispersionOffset, 0.0).b); // 蓝通道向内错开。
		}else{ // 默认无色散：只取一次样本，与未加色散前完全一致。
			sampleColor = CurveToLinear(textureLod(colortex1, sampleCoord, 0.0).rgb); // 样本线性颜色。
		}
		float sampleWeight = max(1.0, currCoc / sampleCoC); // 近处前方样本权重更高，散焦累加时用。
		sampleWeight *= sampleWeight; // 平方加强。
		bool isSelfSample = currCoc >= sampleRadius && sampleDepth >= currDepth; // 样本属于当前点自己。
		bool isBlurredSample = sampleCoC >= sampleRadius && sampleDepth < currDepth; // 样本更近且弥散够大，散焦进来。

		if (isSelfSample){ // 样本属于当前点自己。
			selfColor += sampleColor; // 记为自贡献。
			selfSamples += 1.0; // 自贡献样本数。
		}else if (isBlurredSample){ // 样本散焦进来。
			dof += sampleColor * sampleWeight; // 累加散焦颜色。
			weights += sampleWeight; // 累加权重。
		}else{ // 样本不满足条件，记进中心权重。
			selfWeights += centerWeight; // 累加中心权重。
		}

		#ifdef OMNI_NETHER // 下界额外把深度也累加，供写出屏幕深度使用。
			AccumulateDOFDepth(isSelfSample, isBlurredSample, sampleDepth, sampleWeight, selfDepth, blendedDepth); // 按归属累加深度。
		#endif
	}

	dof += selfColor * (1.0 + selfWeights / selfSamples); // 把自贡献按被拒绝样本的补偿加回来。
	dof /= weights + selfSamples + selfWeights; // 归一化。

	#ifdef OMNI_NETHER // 下界把深度按同一套补偿与归一化后一起返回。
		blendedDepth += selfDepth * (1.0 + selfWeights / selfSamples); // 深度同样补偿。
		blendedDepth /= weights + selfSamples + selfWeights; // 归一化深度。
		return vec4(LinearToCurve(dof), ScreenDepth_From_LinearDepth(blendedDepth)); // 返回曲线编码颜色与换回的屏幕深度。
	#else
		return vec4(LinearToCurve(dof), 0.0); // 返回曲线编码颜色，透明度留零。
	#endif
}

// --- 镜头眩光与光斑 ---
// 只在开启眩光或光斑时编译这一段。
#if defined OMNI_LENS_GLARE || defined OMNI_LENS_FLARE
	#define ORB_FLARE_COUNT	6.0 // 一组鬼影包含几个圆形光斑。
	#define DISTORTION_BARREL 1.0 // 桶形畸变强度，让鬼影沿弧线排布。

	// 求一个偏移向量在桶形畸变后的方向，用于把鬼影沿弧线排列。
	vec2 GetDistOffset(vec2 uv, vec2 pxoffset){
		vec2 tocenter = uv.xy; // 当前点到中心的方向。
		vec3 prep = normalize(vec3(tocenter.y, -tocenter.x, 0.0)); // 与中心方向垂直的轴。
		float angle = length(tocenter.xy) * 2.221 * DISTORTION_BARREL; // 旋转角随距离增大。
		vec3 oldoffset = vec3(pxoffset, 0.0); // 把偏移抬到三维。
		vec3 rotated = oldoffset * cos(angle) + cross(prep, oldoffset) * sin(angle) + prep * dot(prep, oldoffset) * (1.0 - cos(angle)); // 绕轴旋转。
		return rotated.xy; // 取回二维偏移。
	}

	// 画一个带色散的软光点：红绿蓝三个通道沿鬼影方向错开一点，得到彩色边缘。
	vec3 flare(vec2 uv, vec2 pos, float dist, float chromaOffset, float size){
		pos = GetDistOffset(uv, pos); // 先对鬼影位置做桶形畸变。
		float r = max(0.01 - pow(length(uv + (dist - chromaOffset) * pos), 2.4) *( 1.0 / (size * 2.0)), 0.0) * 0.85; // 红色通道。
		float g = max(0.01 - pow(length(uv +  dist                 * pos), 2.4) * (1.0 / (size * 2.0)), 0.0) * 1.0; // 绿色通道。
		float b = max(0.01 - pow(length(uv + (dist + chromaOffset) * pos), 2.4) * (1.0 / (size * 2.0)), 0.0) * 1.5; // 蓝色通道。
		return vec3(r, g, b); // 返回带色散的光点颜色。
	}

	// 画一串沿鬼影方向排列的圆形光斑，颜色从暖到冷渐变。
	vec3 orb(vec2 uv, vec2 pos, float dist, float size){
		vec3 c = vec3(0.0); // 累加结果。
		for (float i = 0.0; i < ORB_FLARE_COUNT; i++){ // 逐个光斑。
			float j = i + 1; // 从一起数的序号。
			float offset = j / (j + 0.1); // 这个光斑在鬼影方向上的位置。
			float colOffset = j / ORB_FLARE_COUNT * 0.5; // 颜色偏移。
			float ss = size / (j + 1.0); // 越靠后的光斑越小。
			c += flare(uv, pos, dist + offset, ss * 2.0, ss) * vec3(1.0 - colOffset, 1.0, 0.5 + colOffset) * j; // 累加并染色放大。
		}
		c += flare(uv, pos, dist + 0.8, 0.05, 3.0 * size) * 0.5; // 末尾再补一个大的柔和光斑。
		return c; // 返回光斑颜色。
	}

	// 画一个环状光环，三个通道同样做色散。
	vec3 ring(vec2 uv, vec2 pos, float dist, float chromaOffset, float blur){
		vec2 uvd = uv * length(uv); // 把坐标按到中心距离放大，得到环而不是点。
		float r = max(1.0 / (1.0 + 250.0 * pow(length(uvd + (dist - chromaOffset) * pos), blur)), 0.0) * 0.8; // 红色通道。
		float g = max(1.0 / (1.0 + 250.0 * pow(length(uvd +  dist                 * pos), blur)), 0.0) * 1.0; // 绿色通道。
		float b = max(1.0 / (1.0 + 250.0 * pow(length(uvd + (dist + chromaOffset) * pos), blur)), 0.0) * 1.5; // 蓝色通道。
		return vec3(r, g, b); // 返回光环颜色。
	}

	// 镜头光斑主入口：按太阳在屏幕上的位置铺开眩光与鬼影，并按太阳可见度与雾浓淡衰减。
	// 输出按管线编码，写进三号画面，稍后由八号与十四号阶段叠加。
	vec3 LensFlare(){
		vec3 lf = vec3(0.0); // 累加结果。
		vec2 coord = texCoord - 0.5; // 当前点相对中心。
		vec2 sunPos = sunCoord - 0.5; // 太阳相对中心。
		coord.x *= aspectRatio; // 按宽高比修正成圆。
		sunPos.x *= aspectRatio; // 太阳位置同样修正。
		float fovFactor = max(gbufferProjection[1][1], 2.0); // 由投影矩阵估计视场，给一个下限。
		#ifdef OMNI_LENS_GLARE // 眩光：沿光线方向拉出细长亮纹。
			vec2 v = coord - sunPos; // 当前点到太阳的方向。
			float dist = length(v); // 距离。
			float gDist = dist * 13.0 / fovFactor; // 按视场归一化。
			float phase = atan2(v) + 0.131; // 方向角加一个固定偏移。
			float gl = 2.0 - saturate(gDist) + sin(phase * 12.0) * saturate(gDist * 2.5 - 0.2); // 细长亮纹。
			gl = gl * gl; // 平方加强。
			gDist = gDist * gDist; // 距离平方。
			gl *= 8e-5 / (gDist * gDist); // 按距离衰减。
			gl = min(gl, 200.0); // 设上限避免过亮。
			lf += vec3(gl * OMNI_GLARE_BRIGHTNESS); // 按眩光亮度累加。
		#endif
		#ifdef OMNI_LENS_FLARE // 光斑：一组鬼影、两个光环和若干散点。
			float size = 0.5 * fovFactor; // 光斑整体大小。
			vec3 fl = vec3(0.0); // 光斑累加。
			fl += orb(coord, sunPos, 0.0, size * 0.01) * 0.1; // 圆形鬼影。
			fl += ring(coord, sunPos,  1.0, 0.02, 1.4) * 0.01; // 远端光环。
			fl += ring(coord, sunPos, -1.0, 0.02, 1.4) * 0.01; // 近端光环。
			fl += flare(coord, sunPos, -2.00, 0.05, size * 0.05) * 0.5; // 一抹大鬼影。
			fl += flare(coord, sunPos, -0.90, 0.02, size * 0.03) * 0.3; // 散点。
			fl += flare(coord, sunPos, -0.70, 0.01, size * 0.06) * 0.5; // 散点。
			fl += flare(coord, sunPos, -0.55, 0.02, size * 0.02) * 0.2; // 散点。
			fl += flare(coord, sunPos, -0.35, 0.02, size * 0.04) * 0.7; // 散点。
			fl += flare(coord, sunPos, -0.25, 0.01, size * 0.15) * vec3(0.3, 0.4, 0.38); // 偏青的大鬼影。
			fl += flare(coord, sunPos, -0.25, 0.02, size * 0.08) * 0.2; // 散点。
			fl += flare(coord, sunPos,  0.05, 0.01, size * 0.03) * 0.1; // 散点。
			fl += flare(coord, sunPos,  0.30, 0.02, size * 0.20) * vec3(0.2, 0.18, 0.14); // 偏暖的鬼影。
			fl += flare(coord, sunPos,  1.20, 0.03, size * 0.10) * 0.2; // 散点。
			lf += fl * (OMNI_FLARE_BRIGHTNESS * 0.3); // 按光斑亮度累加。
		#endif
		lf *= colorSunlight * (sunVisibility * saturate(exp2(1.0 - OMNI_VFOG_DENSITY * 20.0)) / MAIN_OUTPUT_FACTOR); // 按阳光颜色、可见度与雾浓淡衰减。
		return LinearToCurve(lf); // 按管线编码返回。
	}
#endif // 眩光与光斑结束。

// --- 相机动态模糊 ---
// 用上一帧相机把当前表面重投影回屏幕，沿两帧之间的屏幕位移取几个历史位置做平均，模拟快门时间内相机的移动。
// 为什么只做相机运动：没有实体速度缓冲，硬算会把静止物体也拖出鬼影，所以只处理相机移动造成的整屏位移。
// 无效情况（手、覆盖层、传送、越界）都提前返回，让这些像素保持清晰。
vec2 MotionBlurCameraVelocity(vec2 coord, float depth){
	vec3 projection = vec3(coord, depth) * 2.0 - 1.0; // 转负一到一。
	projection = (vec3(vec2(gbufferProjectionInverse[0].x, gbufferProjectionInverse[1].y) * projection.xy, 0.0) + gbufferProjectionInverse[3].xyz) / (gbufferProjectionInverse[2].w * projection.z + gbufferProjectionInverse[3].w); // 逆投影到视空间。
	if (depth < 0.7){ // 手按固定深度偏移补偿相机位移。
		projection += (gbufferPreviousModelView[3].xyz - gbufferModelView[3].xyz) * MC_HAND_DEPTH; // 手的固定偏移。
	}else{ // 普通世界表面。
		projection = mat3(gbufferModelViewInverse) * projection + gbufferModelViewInverse[3].xyz; // 视空间转世界。
		if (depth < 1.0) projection += cameraPosition - previousCameraPosition; // 有限深度才补相机位移。
		projection = mat3(gbufferPreviousModelView) * projection + gbufferPreviousModelView[3].xyz; // 转到上一帧视空间。
	}
	projection = (vec3(gbufferPreviousProjection[0].x, gbufferPreviousProjection[1].y, gbufferPreviousProjection[2].z) * projection + gbufferPreviousProjection[3].xyz) / -projection.z * 0.5 + 0.5; // 投到上一帧屏幕。
	return coord - projection.xy; // 位移等于当前坐标减上一帧坐标。
}

// 相机动态模糊主入口：沿快门方向的中心位置取历史颜色，按质量选项决定样本数。
// 快门角决定拖影长度；抖动选项给采样位置加一点随机，减少采样不足产生的条纹。
vec3 MotionBlur(){
	float materialIDs = floor(texelFetch(colortex6, texelCoord, 0).b * 255.0); // 读当前像素的材质编号。
	float depth = 0.0; // 该像素用于重投影的深度。
	if (materialIDs == MATID_WATER || materialIDs == MATID_ICE){ // 水和冰用含半透明的深度。
		depth = texelFetch(depthtex0, texelCoord, 0).x; // 读零号深度。
	}else{ // 其他表面用不含半透明的深度。
		depth = texelFetch(depthtex1, texelCoord, 0).x; // 读一号深度。
	}
	vec2 velocity = vec2(0.0); // 屏幕位移，默认零。
	#ifdef OMNI_DISABLE_PLAYER_TAA_MOTION_BLUR // 关闭玩家动态模糊时玩家不参与。
		bool blurPixel = depth > 0.7 && materialIDs != MATID_END_PORTAL && materialIDs != MATID_ENTITIES_PLAYER; // 手与玩家都排除。
	#else // 默认只排除手和末地传送门。
		bool blurPixel = depth > 0.7 && materialIDs != MATID_END_PORTAL; // 近处左手以外的世界表面参与。
	#endif
	if (blurPixel){ // 先用宏决定是否参与，再走一条完整的 `if`，避免判断括号被预处理指令切开。
		velocity = MotionBlurCameraVelocity(texCoord, depth); // 算屏幕位移。
	}
	vec3 color = vec3(0.0); // 输出颜色。
	if (length(velocity) < 5e-7){ // 位移极小说明相机没动，直接用历史颜色。
		color = CurveToLinear(texelFetch(colortex7, texelCoord, 0).rgb); // 读七号画面当前颜色。
	}else{ // 相机动了，沿位移方向平均。
		velocity *= OMNI_MOTION_BLUR_SHUTTER_ANGLE / 720.0; // 快门角换算成拖影长度。
		velocity = clamp(velocity, -0.1, 0.1); // 限制单帧拖影上限。
		float steps = OMNI_MOTION_BLUR_QUALITY; // 一侧的采样步数。
		float samples = 0.0; // 有效样本计数。
		float dither = 0.0; // 采样抖动。
		#ifdef OMNI_MOTION_BLUR_DITHER // 开启抖动时给采样位置加噪声。
			dither = InterleavedGradientNoise(gl_FragCoord.xy); // 交错梯度噪声。
		#endif
		for (float i = -steps; i <= steps; i++){ // 沿快门方向对称取样。
			vec2 coord = texCoord.st + velocity / (steps + 1.0) * (i + dither); // 这个样本的坐标。
			if (saturate(coord) == coord){ // 坐标在画面内才采。
				color += CurveToLinear(textureLod(colortex7, coord, 0.0).rgb); // 累加历史颜色。
				samples++; // 计数。
			}
		}
		color.rgb /= samples; // 按有效样本数平均。
	}
	return color; // 返回模糊后的线性颜色。
}

// --- 暗角 ---
// 按到画面中心的距离把四角压暗；`falloff` 是强度，`roundness` 在椭圆与圆形之间插值。
float Vignette(vec2 coord, const float falloff, const float roundness){
	vec2 aCoord = coord * 2.0 - 1.0; // 转负一到一。
	aCoord.x *= mix(1.0, aspectRatio, roundness); // 按圆度修正横坐标。
	float rf = dot(aCoord, aCoord) * falloff * falloff + 1.0; // 距离平方乘强度。
	return 1.0 / (rf * rf); // 取二次衰减。
}
#endif // 文件守卫结束。
