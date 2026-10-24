/*
生成文件：噪声模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库噪声模块：整数哈希、二维与三维值噪声、分形叠加。
调用位置：云、雾、水面细节与测试世界的地形着色；Minecraft 光影由 `/omni-gfx/noise.glsl` 引入。
可复制示例：
    float n = ogxValueNoise3(position * 0.1); // 取一个平滑的三维噪声。
    float f = ogxFbm2(uv * 4.0, 4); // 四层二维分形噪声。
设计原因与取舍：
    全部用整数哈希与插值生成，不读取噪声贴图，因此同一份源能生成 GLSL 与 SPIR-V，
    也能在不启动 Minecraft 的测试世界里重复出图。常数来自旧测试世界的 `noise.glsl`，
    迁移只改名字与类型写法，画面保持一致。
*/
#ifndef OGX_NOISE_INCLUDED
#define OGX_NOISE_INCLUDED

// 数学模块提供夹紧、重映射与圆周率等基础函数。
#include "/omni-gfx/math.glsl"
// 三维整数哈希：把格点坐标与种子混成一个零到一的伪随机数。
float ogxHash13(vec3 p)
{
    p = fract(p * 0.1031); // 先压到小数范围，减少大坐标的精度损失。
    p += dot(p, p.yzx + 33.33); // 三个分量互相混合。
    return fract((p.x + p.y) * p.z); // 取小数部分作为结果。
}

// 二维整数哈希：只需要平面坐标时比三维版本少一半计算。
float ogxHash12(vec2 p)
{
    vec3 p3 = fract(vec3(p.x, p.y, p.x) * 0.1031); // 两个坐标扩成三个分量。
    p3 += dot(p3, p3.yzx + 33.33); // 互相混合，打散相邻格点的规律。
    return fract((p3.x + p3.y) * p3.z); // 零到一的伪随机数。
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

#endif
