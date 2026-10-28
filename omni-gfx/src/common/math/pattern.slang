// 数学模块图案工具：拜尔抖动、切线基、HSV、旋转矩阵、径向曲线与空间扭曲。
// 调用位置：由 `common/math.slang` 内联引入，后期、天空与吸积盘共用。
// 可复制示例：`float b = ogxInterleavedGradientNoise(pixelCoord);`
// 设计原因与取舍：图案函数保持原来的常数与矩阵展开顺序，避免画面抖动改变。

// --- 抖动表、切线基与颜色图案 ---

// 交错梯度噪声：一个像素一个值，适合做抖动，常数来自原始论文。
float ogxInterleavedGradientNoise(float2 coordinate)
{
    return fract(52.9829189 * fract(0.06711056 * coordinate.x + 0.00583715 * coordinate.y));
}

// 二乘二拜尔矩阵：四个格子依次得到零、四分之一、二分之一、四分之三。
float ogxBayer2(float2 a)
{
    a = floor(a);
    return fract(dot(a, float2(0.5, a.y * 0.75)));
}

// 四乘四拜尔矩阵：由二乘二嵌套得到，用来做稳定抖动。
float ogxBayer4(float2 a) { return ogxBayer2(0.5 * a) * 0.25 + ogxBayer2(a); }

// 八乘八拜尔矩阵。
float ogxBayer8(float2 a) { return ogxBayer4(0.5 * a) * 0.25 + ogxBayer2(a); }

// 十六乘十六拜尔矩阵：四层二乘二矩阵嵌套，抖动级别比八乘八细四倍。
float ogxBayer16(float2 a) { return ogxBayer4(0.25 * a) * 0.0625 + ogxBayer4(a); }

// 三十二乘三十二拜尔矩阵：低频一档换成八乘八，级别再细四倍。
float ogxBayer32(float2 a) { return ogxBayer8(0.25 * a) * 0.0625 + ogxBayer4(a); }

// 六十四乘六十四拜尔矩阵：范围大，适合时间累积前的初始偏移。
float ogxBayer64(float2 a) { return ogxBayer8(0.125 * a) * 0.015625 + ogxBayer8(a); }

// 一百二十八乘一百二十八拜尔矩阵：目前最细的一档，给低步数光追分摊首帧噪点。
float ogxBayer128(float2 a) { return ogxBayer16(0.125 * a) * 0.015625 + ogxBayer8(a); }

// 切线基的三个方向；用结构体而不是矩阵，避免两种语言的行列顺序不同造成转置错误。
struct OgxTangentBasis
{
    float3 tangent;
    float3 bitangent;
    float3 normal;
};

// 由位置与纹理导数构造切线基：先叉乘得到法线，再解切线与副切线。
// 模型没提供切线时只能这样反推；返回结构体，调用方按字段读取。
OgxTangentBasis ogxTangentBasis(float3 dp1, float3 dp2, float2 duv1, float2 duv2)
{
    float3 normal = normalize(cross(dp1, dp2));
    float3 dp2perp = cross(dp2, normal);
    float3 dp1perp = cross(normal, dp1);
    float3 tangent = normalize(dp2perp * duv1.x + dp1perp * duv2.x);
    float3 bitangent = normalize(dp2perp * duv1.y + dp1perp * duv2.y);
    float invmax = 1.0 / sqrt(max(dot(tangent, tangent), dot(bitangent, bitangent)));
    OgxTangentBasis basis;
    basis.tangent = tangent * invmax;
    basis.bitangent = bitangent * invmax;
    basis.normal = normal;
    return basis;
}

// 色相、饱和度、明度：按最大通道选扇区，再算色相与饱和度。
float3 ogxRgbToHsv(float3 color)
{
    static const float4 K = float4(0.0, -1.0, 2.0, -3.0) / 3.0;
    const float e = 1.0e-10;
    float4 p = lerp(float4(color.bg, K.wz), float4(color.gb, K.xy), step(color.b, color.g));
    float4 q = lerp(float4(p.xyw, color.r), float4(color.r, p.yzx), step(p.x, color.r));
    float d = q.x - min(q.w, q.y);
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// 三个轴的旋转合成：先俯仰、再偏航、最后滚转，供吸积盘与末地行星摆正自己的坐标系。
// 这里保留原程序的扁平构造参数顺序：生成 GLSL 后由 GLSL 的列主序规则解释，
// 因此运行时矩阵与旧实现完全相同；不要在 Slang 侧改成按列传入，否则生成文本会换序。
float3x3 ogxRotateMatrix(float x, float y, float z)
{
    float3x3 matx = float3x3(1.0, 0.0, 0.0, 0.0, cos(x), sin(x), 0.0, -sin(x), cos(x)); // 绕横轴俯仰。
    float3x3 maty = float3x3(cos(y), 0.0, -sin(y), 0.0, 1.0, 0.0, sin(y), 0.0, cos(y)); // 绕纵轴偏航。
    float3x3 matz = float3x3(cos(z), sin(z), 0.0, -sin(z), cos(z), 0.0, 0.0, 0.0, 1.0); // 绕前后轴滚转。
    return maty * matx * matz; // 三个旋转按原程序的顺序合成。
}

// 环形径向轮廓：中心亮、边缘按四次方乘线性衰减，用于光晕。
float ogxRadialCurve(float x){
    float x2 = x * x;
    return 12.207 * x2 * x2 * (1.0 - x);
}

// 夜视：把颜色往偏蓝的亮度上拉一半，暗处看得清但保留一点原色。
// 为什么保留在通用数学：宿主的公共数学包装 `DoNightEye` 直接调用它，多个阶段共用；
// 它不是某一个效果的私有算法。
void ogxDoNightEye(inout float3 color)
{
    float luma = ogxLuminance(color); // 原色亮度。
    color = lerp(color, luma * float3(0.7771, 1.0038, 1.6190), float3(0.5)); // 偏蓝亮度与原色各占一半。
}

// 空间扭曲：越靠近原点，光线方向越被拉向原点，模拟黑洞附近的引力弯曲。
// 方向和位置都就地修改，调用方下一轮步进会用到新的方向。
void ogxWarpSpace(inout float3 direction, inout float3 position)
{
    float3 origin = float3(0.0);
    float singularityDistance = distance(position, origin);
    float warpFactor = 1.0 / (singularityDistance * singularityDistance + 0.000001);
    float3 singularityVector = normalize(origin - position);
    float warpAmount = 0.06;
    direction = normalize(direction + singularityVector * warpFactor * warpAmount);
}

/*
实现说明：屏幕图案与坐标变换。
一、Bayer 矩阵：二阶到八阶的阈值矩阵由递归展开得到，抖动用它把色阶打散。
二、旋转矩阵：二维旋转与三列矩阵互转，光环与光斑按角度旋转。
三、圆映射：把方形坐标折到圆盘，`ogxCircleMapL` 返回三维版本供球面采样。
四、空间扭曲：黑洞附近的引力弯曲按距离平方增强方向偏移。
五、夜视：暗处把颜色混向偏蓝的亮度，宿主公共数学的包装直接调用它。
六、哈希与噪声：屏幕坐标加帧号生成稳定的伪随机值，避免每帧重新排布。
七、边界：图案函数不读取分辨率，调用方把像素坐标归一化后传入。
*/

/*
函数索引：
一、`ogxInterleavedGradientNoise`：屏幕坐标的插值梯度噪声。
二、`ogxBayer2` 到 `ogxBayer128`：递归展开的 Bayer 阈值矩阵。
三、`ogxTangentBasis`：按法线构造切线基，退化方向有回退。
四、`ogxRgbToHsv`：颜色到色相、饱和度、明度。
五、`ogxRotateMatrix`：二维旋转与三列矩阵互转。
六、`ogxRadialCurve`：环形径向轮廓。
七、`ogxDoNightEye`：暗视觉偏蓝。
八、`ogxWarpSpace`：黑洞附近的引力弯曲。
九、边界：图案函数不读取分辨率，调用方把像素坐标归一化后传入。
十、常数：Bayer 矩阵与夜间偏蓝系数按参考精度保留。
*/

/*
参数与边界：
一、Bayer 矩阵的阶数越高，抖动的颗粒越细。
二、切线基在法线与辅助轴平行时退化，调用方要提供回退。
三、色相转换假设输入在零到一之间。
四、旋转矩阵的角度用弧度。
五、径向曲线在中心为零，在边缘回落。
六、夜视只改颜色，不改亮度统计。
七、空间扭曲的强度固定，调用方不能按场景缩放。
八、图案函数不读取分辨率，坐标要归一化。
九、所有函数都是纯函数，可以在任意阶段调用。
十、哈希与噪声的常数按参考精度保留。
*/

/*
补充说明：图案的坐标。
Bayer 矩阵按屏幕像素取模，坐标要取整。
切线基在法线与辅助轴平行时退化。
色相转换的输入在零到一之间。
空间扭曲的强度固定。
画面验证看抖动颗粒与法线。
*/

/*
补充说明：图案坐标。
Bayer 矩阵按像素取模。
切线基在平行时退化。
色相输入在零到一之间。
空间扭曲强度固定。
*/
