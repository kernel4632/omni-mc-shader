/*
镜头形变的宿主接线：读取 Minecraft 输入、调用通用库并写出结果。
调用位置：原引用 `effects/lens/distortion.glsl` 的程序改为引用本文件。
可复制示例：下方函数保留原有效果入口的签名，调用方式不变。
设计原因与取舍：选项留在效果层，算法在通用库，本文件只做宿主数据与算法之间的转换。
*/
#ifndef OMNI_RENDER_LENS_DISTORTION_INCLUDED
#define OMNI_RENDER_LENS_DISTORTION_INCLUDED
#include "/effects/lens/distortion.glsl"
/*
镜头形变：作用在最终画面上的屏幕空间形变，包含色差、鱼眼（桶形）畸变、像素化与色数。
来源：色差照 Eclipse `dimensions/composite12.fsh` 的 `chromaticAberration` 一比一移植；
  鱼眼照 `dimensions/final.fsh` 的 `FISHEYE_EFFECT` 段；像素化与色数照同文件 `PIXELATED` 与 `MAX_COLORS_PER_CHANNEL` 两段；
  选项名、默认值与取值范围照 Eclipse `lib/settings.glsl` 的对应几行（色差 `:811`、鱼眼 `:827`、像素化 `:820`、色数 `:825`）。
职责：把已经合成好的最终画面按镜头形变重采样：色差让红蓝通道沿屏幕半径错开，
  鱼眼把画面从中心向外卷成桶形，像素化取整块的一个颜色，色数把每个通道压到有限档位。
与既有散景色散的区别：`effects/lens/lens.glsl` 里的 `OMNI_DOF_DISPERSION_MULT` 只在景深采样时对失焦像素做色散，
  只影响开了景深的那部分模糊；本文件是全屏、与景深无关的镜头色差，两者作用对象完全不同，不会重复处理同一批像素。
调用位置：`rendering/final.glsl` 的片元阶段，在算出最终颜色之后、抖动与黑边之前调用 `LensDistortion`。
可复制示例：`color = LensDistortion(colortex1, color, texCoord);`
调用前提：调用方必须先声明 `texCoord`、`finalPixelSize` 与 `aspectRatio`，并把要重采样的源画面作为第一个参数传入。
  为什么源画面由调用方给：开了放大（`FSR`）时最终画面来自八号画面而不是一号画面，形变必须重采样同一张源图，
  否则会把放大结果丢掉、退回低分辨率画面；源图由调用方按当前路径选择，本文件不猜。
设计原因与取舍：
  Eclipse 把色差放在合成十二号、鱼眼与像素化放在最终程序；Omni 把三者统一放在最终程序，
  因为这三项都要按畸变后的坐标重采样已经写完的最终画面，放在同一步只做一次全屏读写。
  为什么不去掉这个文件、直接写进调用方：三项各自成函数、共用一套选项，集中在效果页便于按效果查找与修改。
  默认三个开关都关、色数取零，函数原样返回传入颜色，默认画面完全不变。
*/

// 镜头形变主入口：按选项把源画面重采样后返回；三项都关时原样返回传入颜色。
// 为什么把三项合在一个函数：三者共用同一个输入画面与坐标，分开调用会重复读同一张画面。
// `source` 是要重采样的最终画面：未开放大时是低分辨率的一号画面，开放大时是放大后的八号画面。
vec3 LensDistortion(sampler2D source, vec3 color, vec2 coord){
#if OMNI_CHROMATIC_ABERRATION || OMNI_FISHEYE || OMNI_PIXELATE || OMNI_PIXELATE_COLORS > 1 // 任一项开启时才展开重采样体。
	// 先按像素化或鱼眼定出一个基础采样坐标；两者互斥，优先顺序照 Eclipse 的最终程序，像素化在前。
	vec2 sampleCoord = coord; // 默认原样取样，对应三项里只有色差或色数的情形。
	#if OMNI_PIXELATE // 开启像素化。
		// 像素化：把坐标对齐到方块左上角，整块取同一个点，得到整齐的大色块。
		vec2 blockSize = vec2(OMNI_PIXELATE_STRENGTH); // 每块占多少屏幕像素。
		vec2 blockOrigin = floor(gl_FragCoord.xy / blockSize) * blockSize; // 方块左上角的像素坐标。
		sampleCoord = (blockOrigin + 0.5) * finalPixelSize; // 换成零到一坐标，指向方块左上角像素的中心。
	#elif OMNI_FISHEYE // 未开像素化但开鱼眼。
		// 鱼眼：到中心的距离越远，向内收缩越多，画面边缘被卷起，得到桶形畸变。
		vec2 centered = coord - 0.5; // 相对画面中心。
		float dist = length(centered); // 到中心的距离。
		sampleCoord = centered * (1.0 - OMNI_FISHEYE_STRENGTH * dist * dist) + 0.5; // 等价原式的 `centered * dist2 / dist`，中心处不会零除零。
	#endif

	vec3 warped; // 形变后取到的最终画面色。
	#if OMNI_CHROMATIC_ABERRATION // 开启色差时红蓝通道分别错开取色。
		// 色差：红蓝通道沿屏幕半径错开，绿通道不动；离中心越远错开越多，边缘彩边最明显。
		float noise = InterleavedGradientNoise(gl_FragCoord.xy) - 0.5; // 每像素抖动一点，避免固定图案，作用同 Eclipse 的蓝噪声。
		vec2 caCenter = coord - 0.5; // 相对画面中心，单独取名，避免与上面鱼眼分支的同名局部量在一份源码里撞名。
		float edge = 1.0 - clamp(1.0 - length(caCenter * vec2(aspectRatio, 1.0)) / 200.0, 0.0, 1.0); // 离中心越远权重越大，照原式写成两百的尺度。
		vec2 offset = (caCenter + caCenter * noise) * (OMNI_CHROMATIC_ABERRATION_STRENGTH * edge); // 红蓝各错开这么多。
		warped.r = texture(source, sampleCoord - offset).r; // 红通道向外错开。
		warped.g = texture(source, sampleCoord).g; // 绿通道不动。
		warped.b = texture(source, sampleCoord + offset).b; // 蓝通道向内错开。
	#else // 没开色差时只取一次样本。
		warped = texture(source, sampleCoord).rgb; // 像素化或鱼眼的单次取样。
	#endif

	#if OMNI_PIXELATE_COLORS > 1 // 开启色数时才做量化。
		// 色数：每个通道压到有限档位，模拟低色深画面，与像素化可以叠加。
		float levels = OMNI_PIXELATE_COLORS - 1.0; // 除以档数减一，照原式。
		warped = floor(warped * levels) / levels; // 取整到底部档位。
	#endif
	return warped; // 返回形变后的最终画面色。
#else // 三项都关。
	return color; // 原样返回，默认画面不变。
#endif
}
#endif // OMNI_RENDER_LENS_DISTORTION_INCLUDED
