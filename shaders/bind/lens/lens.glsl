/*
镜头的宿主接线：读取 Minecraft 输入、调用通用库并写出结果。
调用位置：原引用 `effects/lens/lens.glsl` 的程序改为引用本文件。
可复制示例：下方函数保留原有效果入口的签名，调用方式不变。
设计原因与取舍：选项留在效果层，算法在通用库，本文件只做宿主数据与算法之间的转换。
*/
#ifndef OMNI_BIND_LENS_LENS_INCLUDED
#define OMNI_BIND_LENS_LENS_INCLUDED
#include "/effects/lens/lens.glsl"
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
#include "/gfx/post.glsl"
#include "/bind/clarity/antialiasing.glsl"
#include "/common/noise.glsl"

// 景深：弥散圆、散焦范围与散焦合成。
#include "/bind/lens/dof.glsl"
// 镜头眩光与光斑。
#include "/bind/lens/glare.glsl"
// 相机动态模糊。
#include "/bind/lens/motion_blur.glsl"
// --- 暗角 ---
// 按到画面中心的距离把四角压暗；`falloff` 是强度，`roundness` 在椭圆与圆形之间插值。
float Vignette(vec2 coord, const float falloff, const float roundness){
	return gfx_vignette(coord, falloff, roundness, aspectRatio); // 画面纵横比由效果层传入。
}
#endif // OMNI_BIND_LENS_LENS_INCLUDED
