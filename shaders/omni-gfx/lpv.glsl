/*
生成文件：光传播体积模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中按效果分文件夹，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库光传播体积模块：三维彩色间接光的取样、编码与边缘淡出。
调用位置：任何把体素网格里的彩色间接光取回表面的程序；Minecraft 光影由 `shaders/rendering/lighting/lpv.glsl` 调用。
可复制示例：
    `vec4 texel = ogxLpvDecodeSample(stored, vec2(15.0, 24.0));` 解码存下的色相与亮度。
    `vec3 block = ogxLpvBlockLight(texel);` 取回彩色方块光。
    `float sky = ogxLpvSkyLight(texel);` 取回天光。
设计原因与取舍：
    纹理句柄、帧号奇偶与网格尺寸全部由调用方传入，库只收已经取到的四分量样本，
    因此同一份算式能同时用于 GLSL 330 与 SPIR-V，不绑定任何引擎的三维纹理约定。
    编码沿用“色相照原样存、饱和度与天光取对数”的方案，解码必须与编码逐项对齐，
    否则一进一出之后光色会偏，这也是这对函数放在同一个文件里的原因。
*/
#ifndef OGX_LPV_INCLUDED
#define OGX_LPV_INCLUDED

// 光色与解码都要用颜色换算，直接引入颜色模块，它已经带上数学模块。
#include "/omni-gfx/color.glsl"
// 方块光的亮度系数：存下的颜色取值零到十五，除以十五得到零到一。
const float OGX_LPV_BLOCK_BRIGHTNESS = 0.066666;

// 体积光的亮度曲线：平方放大，让弱光抬起来、强光更快饱和。
// 与解码端的曲线必须一致，改一处就要同步另一处，否则光强会整体漂移。
float ogxLpvCurve(float value) { return value * value; }

// 把归一化坐标换成三维纹理坐标：体积边长由调用方给出。
vec3 ogxLpvUvw(vec3 lpvPos, float side) { return lpvPos / side; }

// 把相机相对位置搬进体积中心：加上相机所在格的小数部分，玩家走动时体积按整格平移。
vec3 ogxLpvPosition(vec3 playerPos, vec3 cameraFract, float halfSide)
{
    return playerPos + cameraFract + halfSide;
}

// 解码一个已经取到的体积样本：先按色相还原颜色，再按平方曲线放大亮度并归一到零到一。
// 为什么先当颜色再转 HSV：写入端把亮度压进饱和度通道，读回来必须走同一条逆路径。
// 参数名不用 `sample`：它在 GLSL 4.0 以后是插值限定符，430 的计算程序会直接报语法错误。
vec4 ogxLpvDecodeSample(vec4 texel, vec2 blockSkyRange)
{
    vec3 hsv = ogxRgbToHsv(texel.rgb);
    hsv.z = ogxLpvCurve(hsv.b) * blockSkyRange.x;
    texel.rgb = ogxHsvToRgb(hsv);
    texel.rgb = ogxSaturate(texel.rgb / 15.0);
    return texel;
}

// Eclipse 的 LPV 线性取样入口：按帧号奇偶从两张三维纹理中取一张，再走同一份解码。
// 为什么显式传入两张纹理：参考实现读 texLpv1/texLpv2，库不绑定宿主纹理槽位。
vec4 ogxLpvSampleLinear(vec3 lpvPos, sampler3D lpv1, sampler3D lpv2,
    int frameCounter, float lpvSize, vec2 blockSkyRange)
{
    vec3 texcoord = lpvPos / lpvSize; // 归一化到体积坐标。
    vec4 texel = (frameCounter % 2) == 0
        ? textureLod(lpv1, texcoord, 0.0) : textureLod(lpv2, texcoord, 0.0); // 按帧号二选一。
    return ogxLpvDecodeSample(texel, blockSkyRange); // 解码色相与亮度。
}

// 彩色方块光：亮度系数乘解码后的颜色，供表面照明使用。
vec3 ogxLpvBlockLight(vec4 texel) { return OGX_LPV_BLOCK_BRIGHTNESS * texel.rgb; }

// 天光：先夹到零到一，再平方，暗处变化更柔和。
float ogxLpvSkyLight(vec4 texel)
{
    float skyLight = ogxSaturate(texel.a);
    return skyLight * skyLight;
}

// 写入端的编码：色相照原样，饱和度与天光取对数，压住八位图存不下的动态范围。
vec4 ogxLpvEncode(vec4 value, vec2 blockSkyRange)
{
    vec4 hsvSky = vec4(ogxRgbToHsv(value.rgb), value.a);
    hsvSky.zw = log2(hsvSky.zw + 1.0) / blockSkyRange;
    return vec4(ogxHsvToRgb(hsvSky.xyz), hsvSky.w);
}

// 传播阶段读回上一步结果的解码：与编码严格互逆，指数还原后再减一。
vec4 ogxLpvDecode(vec4 stored, vec2 blockSkyRange)
{
    vec4 hsvSky = vec4(ogxRgbToHsv(stored.rgb), stored.a);
    hsvSky.zw = exp2(hsvSky.zw * blockSkyRange) - 1.0;
    return vec4(ogxHsvToRgb(hsvSky.xyz), hsvSky.w);
}

// 体积边缘淡出：先算到六个面的距离比，三轴相乘后中心满值、边缘归零。
// 为什么要再压一次曲线：直接相乘在角上掉得太快，会看到明显的方形边界。
float ogxLpvRangeFalloff(vec3 lpvPos, float side, float fadeLength)
{
    vec3 cubicRadius = clamp(min((vec3(side) - 1.0 - lpvPos) / fadeLength, lpvPos / fadeLength), vec3(0.0), vec3(1.0));
    float falloff = cubicRadius.x * cubicRadius.y * cubicRadius.z;
    return 1.0 - pow(1.0 - pow(falloff, 1.5), 3.0);
}

// 把体积光混回原来的方块光：淡出乘强度当权重，零强度时原样返回。
vec3 ogxLpvApply(vec3 blockLight, vec4 texel, float falloff, float strength)
{
    return mix(blockLight, texel.rgb, ogxSaturate(falloff * strength));
}

#endif
