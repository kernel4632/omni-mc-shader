/*
加载器输入：照 iterationT `Lib/UniformDeclare.glsl` 一比一声明所有绘制阶段共用的加载器输入量。
调用位置：每个绘制主体最先引入本文件，然后才引入 `common/math.glsl` 和效果文件。
可复制示例：
    `texelFetch(colortex1, texelCoord, 0)`       精确读取一号画面
    `gl_FragCoord.xy * pixelSize`               屏幕坐标换成零到一，`pixelSize` 是自定义输入
    `texture(colortex8, vec3(uv, layer))`       延迟阶段读取预计算大气三维贴图
设计原因与取舍：
    名字、类型、顺序都照原程序，效果文件照原名直接使用，不另起名字。
    原文件第一行引入设置文件；Omni 的选项分散在各效果文件里，所以这里去掉那一行。
    使用 `OMNI_TAA` 等选项的函数要求调用方先引入定义该选项的效果文件。
    三维贴图替换：延迟和合成阶段里，四号、六号、八号画面被加载器换成云噪声和大气数据贴图，
    所以采样器类型由程序自己打开的 `COLORTEX_CLOUDNOISE`、`COLORTEX8_2D` 宏选择，宏名保留原名。
    同一个名字只在这里声明一次；重复声明同一个全局输入会让编译失败。
*/
#ifndef OMNI_UNIFORMS_INCLUDED // 这份声明只引入一次，避免重复声明。
#define OMNI_UNIFORMS_INCLUDED // 置上标记，后续再次引用直接跳过。

// --- 原版提供的玩家、时间和画面输入 ---
uniform int heldItemId; // 主手物品编号，按 `item.properties` 映射，用于手持光源。
uniform int heldBlockLightValue; // 主手方块光源等级，零到十五。
uniform int heldItemId2; // 副手物品编号。
uniform int heldBlockLightValue2; // 副手方块光源等级。
uniform int worldTime; // 世界时间，单位游戏刻，零到两万四千。
uniform int worldDay; // 当前游戏天数，季节与自定义月亮轨道的累积时间用它。
uniform int frameCounter; // 帧序号，驱动时间噪声与抖动序列。
uniform float frameTime; // 上一帧用时，单位秒。
uniform float frameTimeCounter; // 累计运行秒数，驱动动画。
uniform float sunAngle; // 太阳角度，零到一表示一整天。
uniform vec3 sunPosition; // 太阳或月亮在视空间里的方向，由加载器提供；氛围效果用它判断昼夜。
uniform float aspectRatio; // 画面宽高比。
uniform float viewWidth; // 画面宽度，单位像素。
uniform float viewHeight; // 画面高度，单位像素。
uniform float near; // 近裁剪面距离，单位米。
uniform float far; // 远裁剪面距离，单位米。
uniform vec3 cameraPosition; // 相机世界绝对位置。
uniform vec3 previousCameraPosition; // 上一帧相机位置，用于重投影。
uniform mat4 gbufferModelView; // 相机相对世界到视空间。
uniform mat4 gbufferModelViewInverse; // 视空间回到相机相对世界。
uniform mat4 gbufferPreviousModelView; // 上一帧相机变换。
uniform mat4 gbufferProjection; // 视空间到裁剪空间。
uniform mat4 gbufferProjectionInverse; // 裁剪空间回到视空间。
uniform mat4 gbufferPreviousProjection; // 上一帧投影。
uniform mat4 shadowProjection; // 阴影相机投影。
uniform mat4 shadowModelView; // 世界到阴影相机视空间。
uniform mat4 shadowModelViewInverse; // 阴影相机视空间回到世界。
uniform float wetness; // 湿润度，按半衰期平滑的降雨强度。
uniform ivec2 eyeBrightnessSmooth; // 平滑眼部亮度，横轴方块光、纵轴天空光，零到两百四十。
uniform int isEyeInWater; // 眼睛所在介质：零空气、一水、二岩浆、三细雪。
uniform float nightVision; // 夜视强度。
uniform float blindness; // 失明强度。
uniform int hideGUI; // 是否隐藏界面，标题计数等调试显示据此关闭。
uniform float darknessFactor; // 黑暗效果强度。
uniform float darknessLightFactor; // 黑暗效果的脉动亮度。

// --- `pipeline.properties` 里定义的自定义输入 ---
uniform vec2 taaJitter; // 本帧抖动，十六帧序列除以分辨率。
uniform vec2 screenSize; // 画面尺寸，单位像素。
uniform vec2 pixelSize; // 一个像素在零到一坐标里的大小。
uniform float eyeBrightnessSmoothCurved; // 天空光亮度的曲线平滑值，自动曝光与洞穴判断用。
uniform float eyeBrightnessZeroSmooth; // 完全没有天空光的平滑标记。
uniform float eyeBrightnessOneSmooth; // 天空光满值的平滑标记，雨雪倾斜与云影淡出用。
uniform float eyeSnowySmooth; // 所在群系下雪的平滑标记。
uniform float eyeNoPrecipitationSmooth; // 所在群系不降水的平滑标记。
uniform float eyeRxSmooth; // 视角俯仰角速度的平滑值，镜头效果用。
uniform float eyeRySmooth; // 视角偏航角速度的平滑值。
uniform float isSneakingSmooth; // 潜行状态的平滑值，潜行暗角用。

// --- 远景：只在加载远景模组时存在 ---
#ifdef DISTANT_HORIZONS // 没有远景模组时不声明下面这些名字。
	uniform float dhNearPlane; // 远景近裁剪面距离。
	uniform float dhFarPlane; // 远景远裁剪面距离。
	uniform int dhRenderDistance; // 远景渲染距离，单位方块。
	uniform mat4 dhProjection; // 远景投影。
	uniform mat4 dhProjectionInverse; // 远景逆投影。
	uniform mat4 dhPreviousProjection; // 上一帧远景投影。

	uniform sampler2D dhDepthTex0; // 远景完整深度。
	uniform sampler2D dhDepthTex1; // 远景不含半透明的深度。
#endif // 远景输入结束。

// --- 中间画面与深度：用途见 `rendering/buffers.glsl` ---
uniform sampler2D colortex0; // 零号：贴图色、天体颜色、雨遮罩。
uniform sampler2D colortex1; // 一号：场景曲线编码颜色。
uniform sampler2D colortex2; // 二号：全局光历史、天空盒、云影、统计像素。
uniform sampler2D colortex3; // 三号：不透明法线光照图、反射、镜头光斑。
uniform sampler2D colortex5; // 五号：高光材质与泛光。
uniform sampler2D colortex7; // 七号：焦散法线方块与时间抗锯齿历史。
uniform sampler2D colortex10; // 十号：低分辨率体积云的加色与透过率，只在体积云低分辨率模式下有值。
uniform sampler2D depthtex0; // 含半透明的深度。
uniform sampler2D depthtex1; // 不含半透明的深度。

uniform sampler2D noisetex; // 六十四像素蓝噪声 `texture/noise.png`。

// 延迟阶段四号、六号被替换成两张三维云噪声，程序自己打开 `COLORTEX_CLOUDNOISE` 选择三维采样器。
#ifdef COLORTEX_CLOUDNOISE
	uniform sampler3D colortex4; // 一百二十八立方云噪声。
	uniform sampler3D colortex6; // 三十二立方细节云噪声。
#else
	uniform sampler2D colortex4; // 半透明法线光照图。
	uniform sampler2D colortex6; // 半透明颜色材质与水遮罩。
#endif // 云噪声选择结束。

// 一点一六点五以后大气数据挂在八号画面上，更早的版本挂在二号深度上；最终阶段打开 `COLORTEX8_2D` 读普通二维画面。
#if MC_VERSION >= 11605
	#ifdef COLORTEX8_2D
		uniform sampler2D colortex8; // 放大输出画面。
	#else
		uniform sampler3D colortex8; // 预计算大气三维贴图。
	#endif // 八号类型选择结束。
	uniform sampler2D depthtex2; // 不含手的深度。
#else
	#ifdef COLORTEX8_2D
		uniform sampler2D depthtex2; // 旧版本二号深度。
	#else
		uniform sampler3D depthtex2; // 旧版本大气三维贴图。
	#endif // 旧版本类型选择结束。
#endif // 版本选择结束。

// --- Omni 额外输入：原程序没有声明，保留下来的 Omni 功能需要 ---
// 光传播体积的注入阶段用它算天体高度；原程序没有任何文件声明这个名字，所以放这里不会重复声明。
uniform vec3 shadowLightPosition; // 当前阴影光源的视空间方向。
#endif // 文件守卫结束。
