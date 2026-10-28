/*
生成文件：噪声模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中按效果分文件夹，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库噪声模块：整数哈希、二维与三维值噪声、分形叠加。
调用位置：云、雾、水面细节与测试世界的地形着色；Minecraft 光影由 `/omni-gfx/common/noise.glsl` 引入。
可复制示例：
    float n = ogxValueNoise3(position * 0.1); // 取一个平滑的三维噪声。
    float f = ogxFbm2(uv * 4.0, 4); // 四层二维分形噪声。
设计原因与取舍：
    大多数噪声用整数哈希与插值生成，不依赖贴图；少数函数按调用方要求读取蓝噪声或云噪声贴图，
    纹理句柄由参数传入。因此同一份源能生成 GLSL 与 SPIR-V，也能在不启动 Minecraft 的测试世界里重复出图。
    常数来自旧测试世界的 `noise.glsl`，迁移只改名字与类型写法，画面保持一致。
*/
#ifndef OGX_NOISE_INCLUDED
#define OGX_NOISE_INCLUDED

// 数学模块提供夹紧、重映射与圆周率等基础函数。
#include "/omni-gfx/common/math.glsl"
// 三维整数哈希：把格点坐标与种子混成一个零到一的伪随机数。
float ogxHash13(vec3 p) // 当前步骤的中间量。
{
    p = fract(p * 0.1031); // 先压到小数范围，减少大坐标的精度损失。
    p += dot(p, p.yzx + 33.33); // 三个分量互相混合。
    return fract((p.x + p.y) * p.z); // 取小数部分作为结果。
}

// 二维整数哈希：只需要平面坐标时比三维版本少一半计算。
float ogxHash12(vec2 p)
{
    vec3 p3 = fract(vec3(p.x, p.y, p.x) * 0.1031); // 两个坐标扩成三个分量。
    p3 += dot(p3, p3.yzx + 19.19); // 参考实现的混合常数。
    return fract((p3.x + p3.y) * p3.z); // 零到一的伪随机数。
}

// 标量哈希：Eclipse 的 `hash11` 与极光哈希是同一算式，库只保留一个实现。
float ogxHash11(float p)
{
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

// 三分量哈希：一个标量序号变成互相独立的三维随机值。
vec3 ogxHash31(float p)
{
    vec3 p3 = fract(vec3(p) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xxy + p3.yzz) * p3.zyx);
}

// 二维坐标的整数哈希：先把两个坐标转成整数，再走三次整数混合。
uvec3 ogxHashUint3(vec2 s)
{
    uvec3 x = uvec3(uint(s.x), uint(s.y), uint(s.x) ^ uint(s.y));
    const uint k = 1103515245u;
    x = ((x >> 8u) ^ x.yzx) * k;
    x = ((x >> 8u) ^ x.yzx) * k;
    x = ((x >> 8u) ^ x.yzx) * k;
    return x;
}

// 二维向量哈希：把平面格点变成一个二维随机方向，供旋度噪声与雨点涟漪定位。
// 与标量哈希共用同一组无理数，三个分量互相混合后再取两次小数部分。
vec2 ogxHash22(vec2 p)
{
    vec3 p3 = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973)); // 两个坐标扩成三个分量。
    p3 += dot(p3, p3.yzx + 19.19); // 三个分量互相打散。
    return fract((vec2(p3.x, p3.x) + vec2(p3.y, p3.z)) * vec2(p3.z, p3.y)); // 取出两个独立的小数。
}

// 二维梯度噪声：四个角点各取一个随机方向，与格内偏移点乘后按平滑曲线插值。
// 返回的是解析梯度，不是噪声值；旋度噪声只关心梯度方向，所以这里直接给出两个分量的偏导。
vec2 ogxPerlinGradient2(vec2 coord)
{
    vec2 i = floor(coord); // 格子角点。
    vec2 f = fract(coord); // 格内偏移。
    vec2 u = f * f * (3.0 - 2.0 * f); // 插值权重。
    vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0); // 梯度权重，照 Eclipse 的写法保留。
    vec2 g0 = normalize(ogxHash22(i) - vec2(0.5)); // 左下方向。
    vec2 g1 = normalize(ogxHash22(i + vec2(1.0, 0.0)) - vec2(0.5)); // 右下方向。
    vec2 g2 = normalize(ogxHash22(i + vec2(0.0, 1.0)) - vec2(0.5)); // 左上方向。
    vec2 g3 = normalize(ogxHash22(i + vec2(1.0, 1.0)) - vec2(0.5)); // 右上方向。
    float v0 = dot(g0, f); // 四个角点与偏移的点乘。
    float v1 = dot(g1, f - vec2(1.0, 0.0));
    float v2 = dot(g2, f - vec2(0.0, 1.0));
    float v3 = dot(g3, f - vec2(1.0, 1.0));
    vec2 omu = vec2(1.0) - u; // 反向权重。
    return vec2(((v1 - v0) * omu.y + (v3 - v2) * u.y) * du.x,
                  ((v2 - v0) * omu.x + (v3 - v1) * u.x) * du.y); // 两个方向的偏导。
}

// 二维旋度：把梯度旋转九十度，得到无散度的矢量场，卷云的丝状弯曲靠它。
vec2 ogxCurl2D(vec2 coord)
{
    vec2 gradient = ogxPerlinGradient2(coord); // 先取梯度。
    return vec2(gradient.y, -gradient.x); // 旋转九十度就是旋度。
}

// 白噪声：两个坐标点乘一组无理数后取正弦，成本只有一个点乘与一次正弦。
// 为什么不用哈希：需要连续坐标上的随机值时，正弦哈希不会在整数格上出现明显的方块。
float ogxWhiteNoise(vec2 coord)
{
    return fract(sin(dot(coord, vec2(12.9898, 78.233))) * 43758.5453);
}

// 随时间滚动的白噪声：每帧给坐标加一个小偏移，静止画面上不会留下固定花纹。
float ogxWhiteNoiseTemporal(vec2 coord, float time)
{
    return ogxWhiteNoise(coord + 0.07 * fract(time));
}

// 三角分布噪声：把均匀分布先开方再减符号，取值集中在零附近，两端衰减。
// 抖动要的是这种“多数很小、少数较大”的分布，均匀分布会让画面出现均匀的沙粒感。
float ogxTriangleNoise(vec2 coord, float time)
{
    float center = ogxWhiteNoiseTemporal(coord, time) * 2.0 - 1.0;
    float shaped = center * inversesqrt(max(abs(center), 1e-10));
    shaped = max(-1.0, shaped);
    return shaped - sign(center);
}

// 整数哈希：三次“右移异或再乘常数”，把整数格打散成不相关的三个分量。
// 写法来自 `Inigo Quilez` 的整数哈希；末地雾按整数格重复取样，需要每个显卡逐位一致的结果。
uvec3 ogxIntegerHash3(uvec3 x)
{
    const uint k = 1103515245u; // 线性同余发生器常用的乘数，异或后能把相邻格彻底打散。
    x = ((x >> 8u) ^ x.yzx) * k; // 第一次：每个分量掺入下一个分量的高二十四位。
    x = ((x >> 8u) ^ x.yzx) * k; // 第二次：再打散一轮，消除一轮不够时的相关性。
    x = ((x >> 8u) ^ x.yzx) * k; // 第三次：三轮之后三个分量的每一位都互相影响。
    return x; // 返回三个独立的整数随机值。
}

// 三维值噪声：八个格点各取哈希，再按平滑曲线插值。
float ogxValueNoise3(vec3 p)
{
    vec3 i = floor(p); // 所在格子的整数角。
    vec3 f = fract(p); // 格子内的小数位置。
    f = f * f * (3.0 - 2.0 * f); // 平滑曲线让格子边界没有折线。
    float n000 = ogxHash13(i + vec3(0.0, 0.0, 0.0)); // 八个角点。
    float n100 = ogxHash13(i + vec3(1.0, 0.0, 0.0));
    float n010 = ogxHash13(i + vec3(0.0, 1.0, 0.0));
    float n110 = ogxHash13(i + vec3(1.0, 1.0, 0.0));
    float n001 = ogxHash13(i + vec3(0.0, 0.0, 1.0));
    float n101 = ogxHash13(i + vec3(1.0, 0.0, 1.0));
    float n011 = ogxHash13(i + vec3(0.0, 1.0, 1.0));
    float n111 = ogxHash13(i + vec3(1.0, 1.0, 1.0));
    float nx00 = mix(n000, n100, f.x); // 先沿横向插值。
    float nx10 = mix(n010, n110, f.x);
    float nx01 = mix(n001, n101, f.x);
    float nx11 = mix(n011, n111, f.x);
    float nxy0 = mix(nx00, nx10, f.y); // 再沿纵向插值。
    float nxy1 = mix(nx01, nx11, f.y);
    return mix(nxy0, nxy1, f.z); // 最后沿深度插值。
}

// 二维值噪声：四个角点插值，适合云层的平面形状与水面细节。
float ogxValueNoise2(vec2 p)
{
    vec2 i = floor(p); // 格子角点。
    vec2 f = fract(p); // 格内位置。
    f = f * f * (3.0 - 2.0 * f); // 平滑曲线。
    float a = ogxHash12(i); // 四个角。
    float b = ogxHash12(i + vec2(1.0, 0.0));
    float c = ogxHash12(i + vec2(0.0, 1.0));
    float d = ogxHash12(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y); // 双线性插值。
}

// 二维分形叠加：每层频率翻倍、权重减半，得到自然起伏。
float ogxFbm2(vec2 p, int octaves)
{
    float sum = 0.0; // 累加结果。
    float amplitude = 0.5; // 当前层权重。
    for (int i = 0; i < octaves; i++) // 层数由调用方控制。
    {
        sum += ogxValueNoise2(p) * amplitude; // 加入当前层。
        p = p * 2.03 + vec2(17.0, 31.0); // 频率翻倍并偏移，减少层间重合。
        amplitude *= 0.5; // 高层权重减半。
    }
    return sum; // 零到一附近。
}

// 三维分形叠加：每层频率翻倍、权重减半，供云的细节与雾团使用。
float ogxFbm3(vec3 p, int octaves)
{
    float sum = 0.0; // 累加结果。
    float amplitude = 0.5; // 当前层权重。
    for (int i = 0; i < octaves; i++) // 固定上限，避免不同显卡的循环次数差异。
    {
        sum += ogxValueNoise3(p) * amplitude; // 加入当前层。
        p = p * 2.03 + vec3(17.0, 9.0, 31.0); // 频率翻倍并偏移。
        amplitude *= 0.5; // 高层权重减半。
    }
    return sum; // 大致零到一之间。
}

// 三维扭曲：用三个低频噪声把采样坐标推开，打断值噪声的网格重复。
vec3 ogxWarp3(vec3 p, float strength)
{
    vec3 offset = vec3(ogxValueNoise3(p + vec3(0.0, 0.0, 0.0)), // 横向偏移。
                           ogxValueNoise3(p + vec3(31.4, 17.2, 5.7)), // 纵向偏移。
                           ogxValueNoise3(p + vec3(7.9, 43.1, 23.6))) - 0.5; // 深度偏移。
    return p + offset * strength; // 偏移量按强度缩放后加到原坐标。
}

// 三维噪声查表：把三维格点映射到二维噪声图，再用高度做一次插值。
// 为什么用查表：噪声图的纹素已经做过低差异处理，比现场算哈希更均匀，也更快。
// 该函数被雾、降水高光与水面共用，因此放在噪声模块，而不是某一个效果里。
float ogxFogNoise(vec3 position, sampler2D noiseTexture)
{
    vec3 p = floor(position); // 整数格。
    vec3 f = position - p; // 格内小数偏移。
    f = f * f * (3.0 - 2.0 * f); // 三次曲线平滑小数部分。
    vec2 uv = 17.0 * p.z + p.xy + f.xy; // 把三维格点映射到二维噪声坐标。
    vec2 n = textureLod(noiseTexture, (uv + 0.5) / 64.0, 0.0).zw; // 读取噪声图的后两个通道。
    return mix(n.x, n.y, f.z); // 按高度做一次插值。
}

// 可按贴图边长缩放的三维查表：吸积盘与体积云用不同分辨率的同一张噪声图。
// 为什么与 `ogxFogNoise` 并存：雾固定用六十四像素的图，吸积盘则由调用方传 512，合并会改画面。
float ogxTexture3dNoise(vec3 position, sampler2D noiseTexture, float noiseResolution)
{
    vec3 p = floor(position); // 整数格决定用贴图哪一块。
    vec3 b = fract(position); // 格内偏移用于插值。
    b = b * b * (3.0 - 2.0 * b); // 三次平滑，格与格之间不出现硬边。
    vec2 uv = 17.0 * p.z + p.xy + b.xy; // 把三层格子压到二维坐标，十七是原程序打散层数的常数。
    vec2 rg = textureLod(noiseTexture, (uv + 0.5) / noiseResolution, 0.0).zx; // 取两张通道，零号层级与原来的即时采样一致。
    return mix(rg.x, rg.y, b.z); // 按格内高度在两层之间插值。
}

// 云状分形噪声：四层不同频率的三维噪声叠加，供吸积盘等体积细节使用。
// `shift` 是每层之间的时间位移，让细节缓慢流动而不是整块平移。
float ogxCloudFbm(vec3 position, vec3 shift, sampler2D noiseTexture, float noiseResolution)
{
    const int octaves = 4; // 四层就够，再多在远景里看不出来。
    const float octAlpha = 0.87; // 每层权重只衰减一成多，细节保留得多。
    const float octScale = 2.5; // 每层频率放大二点五倍，避免相邻层太像。
    const float octShift = (octAlpha / octScale) / float(octaves); // 层间偏移，把结果抬回零附近。
    float accum = 0.0; // 累积噪声。
    float alpha = 0.5; // 第一层权重。
    for (int i = 0; i < octaves; i++) // 逐层叠加。
    {
        accum += alpha * ogxTexture3dNoise(position, noiseTexture, noiseResolution); // 加这一层。
        position = (position + shift) * octScale; // 抬高频率并错开时间。
        alpha *= octAlpha; // 权重衰减。
    }
    return accum + octShift; // 返回归一化后的噪声。
}

#endif
