/*
生成文件：采样模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库采样模块：蓝噪声、时间抖动、拜尔抖动、纹理平滑过滤、旋转网格超采样与抗锯齿抖动序列。
调用位置：任何需要每像素或每帧不同采样偏移的程序；Minecraft 光影由 `/omni-gfx/sampling.glsl` 引入。
可复制示例：
    vec2 n = ogxBlueNoise(noiseTexture, ivec2(pixel)); // 取一张蓝噪声。
    float d = ogxBayerTemporal(ivec2(pixel), 0); // 取每帧变化的拜尔值。
    vec4 c = ogxSmoothFilter(albedo, uv, textureSize); // 平滑过滤后的取样。
    vec2 j = ogxTaaJitter(frame, true); // 四帧一循环的抗锯齿抖动。
设计原因与取舍：
    噪声纹理、像素坐标和帧号全部由调用方传入，库不依赖任何引擎全局量。
    静态蓝噪声按六十四像素平铺；时间偏移用黄金比与塑料比错开，避免相邻帧重叠。
    取像素只用显式整数坐标，不用硬件过滤，因此同一份源能直接生成 SPIR-V 与 GLSL。
    超采样需要屏幕空间导数，参考实现直接调用导数内置函数；这里改成由调用方传进来，
    库因此仍然是纯函数，也能在没有屏幕导数的程序里复用。
*/
#ifndef OGX_SAMPLING_INCLUDED
#define OGX_SAMPLING_INCLUDED

// 数学模块提供拜尔矩阵与两个时间步长。
#include "/omni-gfx/math.glsl"
// 显式取一个像素；Slang 的 `Load` 在生成 GLSL 时换成 `texelFetch`，两边语义相同。
vec4 ogxTexelFetch(sampler2D tex, ivec2 pixel, int level)
{
    return texelFetch(tex, pixel, level);
}

// 从蓝噪声纹理取当前像素的二维偏移；纹理边长六十四，按像素坐标取模平铺。
vec2 ogxBlueNoise(sampler2D noiseTexture, ivec2 pixel)
{
    return ogxTexelFetch(noiseTexture, pixel % 64, 0).xy;
}

// 加上帧号偏移，得到每帧变化、六十四帧一循环的二维抖动。
vec2 ogxBlueNoiseTemporal(sampler2D noiseTexture, ivec2 pixel, int frame)
{
    vec2 base = ogxBlueNoise(noiseTexture, pixel);
    return fract(base + vec2(OGX_GOLDEN_RATIO, OGX_PLASTIC_RATIO) * float(frame % 64));
}

// 每帧平移的拜尔抖动，一百二十八帧一循环，适合需要低差异序列的场合。
// 黄金比步进让相邻帧的偏移不重复，同时保持单帧内的空间分布。
float ogxBayerTemporal(ivec2 pixel, int frame)
{
    return fract(ogxBayer64(vec2(pixel)) + OGX_GOLDEN_RATIO * float(frame % 128));
}

// 平滑过滤：先在纹素坐标里用平滑曲线重排采样点，再回纹理坐标取样。
// 为什么先转纹素坐标：平滑曲线必须落在相邻两个纹素的中心之间，直接对零到一的纹理坐标做会随尺寸漂移。
// 纹理采样走显式层级零，调用方不用保证导数存在。
vec4 ogxSmoothFilter(sampler2D tex, vec2 uv, vec2 resolution)
{
    vec2 texel = uv * resolution + 0.5; // 转成纹素坐标，并把中心挪到半像素。
    vec2 whole = floor(texel); // 采样点所在纹素的整数部分。
    vec2 fraction = fract(texel); // 纹素内的小数位置。
    texel = whole + (fraction * fraction) * (3.0 - 2.0 * fraction); // 平滑曲线把小数位置推向两端。
    texel = texel / resolution - 0.5 / resolution; // 换回纹理坐标，并补偿半纹素。
    return textureLod(tex, texel, 0.0); // 读回过滤后的颜色。
}

// 阴影贴图的平滑过滤：坐标是三分量，第三分量是比较值；其余步骤与上一函数相同。
// 为什么阴影要单独一份：阴影采样器带比较，取回的是零到一的可见度而不是颜色。
float ogxShadowSmoothFilter(sampler2DShadow tex, vec3 uv, float resolution)
{
    vec2 texel = uv.xy * resolution + 0.5; // 水平两分量转纹素坐标。
    vec2 whole = floor(texel); // 所在纹素。
    vec2 fraction = fract(texel); // 纹素内位置。
    texel = whole + (fraction * fraction) * (3.0 - 2.0 * fraction); // 平滑重排采样点。
    texel = texel / resolution - 0.5 / resolution; // 换回纹理坐标。
    return textureLod(tex, vec3(texel, uv.z), 0.0); // 按比较值取可见度。
}

// 最近点取样：把纹理坐标拉回纹素中心附近，再按屏幕上的纹素大小决定拉回多少。
// 为什么按屏幕纹素缩放：贴图在远处时一个屏幕像素覆盖多个纹素，完全拉回中心会闪；
// 按覆盖率插值才能让细节平滑消失，而不是逐帧跳动。
vec4 ogxSampleNearest(sampler2D tex, vec2 uv, vec2 pixelSize, vec2 du, vec2 dv, vec2 texelScreenSize)
{
    vec2 texelCoords = uv / pixelSize; // 转成纹素坐标。
    vec2 texelCenter = round(texelCoords) - 0.5; // 最近纹素的中心。
    vec2 texelOffset = texelCoords - texelCenter; // 离中心的偏移。
    texelOffset = (texelOffset - 0.5) * pixelSize / texelScreenSize + 0.5; // 按屏幕纹素大小缩放偏移。
    texelOffset = clamp(texelOffset, vec2(0.0), vec2(1.0)); // 夹在纹素内。
    return textureGrad(tex, (texelCenter + texelOffset) * pixelSize, du, dv); // 用屏幕导数选层级，避免摩尔纹。
}

// 旋转网格的四个子样本位置：绕纹素中心转四十五度，坐标范围在正负零点三七五之间。
vec2 ogxRgssOffset(int index)
{
    if (index == 0) return vec2(0.125, 0.375); // 右下。
    if (index == 1) return vec2(-0.125, -0.375); // 左上。
    if (index == 2) return vec2(0.375, -0.125); // 右上。
    return vec2(-0.375, 0.125); // 左下。
}

// 旋转网格超采样：四个旋转四十五度的子样本，再按贴图缩放程度与最近点取样混合。
// 为什么按缩放混合：缩小时子样本能压住闪烁，放大时最近点更锐利，两者切换要平滑。
vec4 ogxRgssSample(sampler2D tex, vec2 uv, vec2 pixelSize, vec2 du, vec2 dv)
{
    vec2 texelScreenSize = sqrt(du * du + dv * dv); // 一个屏幕像素在各方向的纹素覆盖量。
    float maxTexelSize = max(texelScreenSize.x, texelScreenSize.y); // 较大的那个方向。
    float minPixelSize = min(pixelSize.x, pixelSize.y); // 贴图最小纹素边长。
    float blendFactor = smoothstep(minPixelSize, minPixelSize * 2.0, maxTexelSize); // 缩得越多越偏向超采样。
    float minDerivative = min(length(du), length(dv)); // 两个方向的导数长度。
    float maxDerivative = max(length(du), length(dv));
    float mipLevel = max(0.0, log2(sqrt(minDerivative * maxDerivative) / minPixelSize)); // 按几何平均选层级。
    vec4 rgss = vec4(0.0); // 四个子样本的累加。
    for (int i = 0; i < 4; i++)
    {
        vec2 corner = ogxRgssOffset(i); // 旋转网格上的第 i 个子样本。
        rgss += textureLod(tex, uv + corner * pixelSize, mipLevel); // 带层级采样。
    }
    rgss *= 0.25; // 四个样本取平均。
    vec4 nearest = ogxSampleNearest(tex, uv, pixelSize, du, dv, texelScreenSize); // 最近点结果。
    return mix(nearest, rgss, blendFactor); // 按缩放程度混合。
}

// 抗锯齿抖动序列：`responsive` 为真时用四帧循环，否则用八帧的哈尔顿序列。
// 为什么两套：快速移动的画面需要更短的历史，静止画面用八帧能把边缘修得更平。
vec2 ogxTaaJitter(int frame, bool responsive)
{
    if (responsive)
    {
        int index = frame % 4; // 四帧一循环。
        if (index == 0) return vec2(-0.125, -0.875); // 左上。
        if (index == 1) return vec2(0.875, -0.125); // 右上。
        if (index == 2) return vec2(0.125, 0.875); // 右下。
        return vec2(-0.875, 0.125); // 左下。
    }
    int index = frame % 8; // 八帧一循环。
    if (index == 0) return vec2(1.0, -3.0) / 8.0; // 第一点。
    if (index == 1) return vec2(-1.0, 3.0) / 8.0; // 第二点。
    if (index == 2) return vec2(5.0, 1.0) / 8.0; // 第三点。
    if (index == 3) return vec2(-3.0, -5.0) / 8.0; // 第四点。
    if (index == 4) return vec2(-5.0, 5.0) / 8.0; // 第五点。
    if (index == 5) return vec2(-7.0, -1.0) / 8.0; // 第六点。
    if (index == 6) return vec2(3.0, 7.0) / 8.0; // 第七点。
    return vec2(7.0, 7.0) / 8.0; // 第八点。
}
// 两个互质基数：二与三，和参考包的低差异序列一致。
// 哈尔顿序列：把序号写成给定基数的小数，逐位排在小数点之后，得到低差异采样。
// 用途与蓝噪声相同，但不需要贴图；二分与三分基数的二维版本分布最均匀。
float ogxHalton2(int index)
{
    float result = 0.0;
    float fraction = 0.5;
    int i = max(index, 1);
    while (i > 0)
    {
        result += fraction * float(i & 1);
        i >>= 1;
        fraction *= 0.5;
    }
    return result;
}

// 三维 Halton 序列：体素与体积采样用低差异点减少噪点。
float ogxHalton3(int index)
{
    float result = 0.0;
    float fraction = 1.0 / 3.0;
    int i = max(index, 1);
    while (i > 0)
    {
        result += fraction * float(i % 3);
        i /= 3;
        fraction /= 3.0;
    }
    return result;
}

#endif
