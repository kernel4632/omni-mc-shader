// 测试世界的噪声函数：整数哈希、三维值噪声与分形叠加。
// 调用位置：云层与地形着色器共同引入；只提供纯计算，不读取任何引擎状态。
// 设计原因与取舍：不引入纹理，保证不启动 Minecraft 也能独立出图；常数固定，重复运行画面一致。

// 三维整数哈希：把格点坐标与种子混成一个零到一的伪随机数。
float hash13(vec3 p)
{
    p = fract(p * 0.1031);  // 先压到小数范围，减少大坐标的精度损失。
    p += dot(p, p.yzx + 33.33);  // 三个分量互相混合。
    return fract((p.x + p.y) * p.z);  // 取小数部分作为结果。
}

// 三维值噪声：八个格点各取哈希，再按平滑曲线插值。
float valueNoise(vec3 p)
{
    vec3 i = floor(p);  // 所在格子的整数角。
    vec3 f = fract(p);  // 格子内的小数位置。
    f = f * f * (3.0 - 2.0 * f);  // 平滑曲线让格子边界没有折线。
    float n000 = hash13(i + vec3(0.0, 0.0, 0.0));  // 八个角点。
    float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
    float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
    float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
    float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
    float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
    float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
    float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
    float nx00 = mix(n000, n100, f.x);  // 先沿横向插值。
    float nx10 = mix(n010, n110, f.x);
    float nx01 = mix(n001, n101, f.x);
    float nx11 = mix(n011, n111, f.x);
    float nxy0 = mix(nx00, nx10, f.y);  // 再沿纵向插值。
    float nxy1 = mix(nx01, nx11, f.y);
    return mix(nxy0, nxy1, f.z);  // 最后沿深度插值。
}

// 二维整数哈希：云层只需要平面坐标，二维版本比三维少一半采样。
// 哈希只做乘加与小数截取，不读取纹理，换机器也得到同一片云。
float hash12(vec2 p)
{
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);  // 三个分量来自两个坐标。
    p3 += dot(p3, p3.yzx + 33.33);  // 互相混合。
    return fract((p3.x + p3.y) * p3.z);  // 零到一。
}

// 二维值噪声：四个角点插值，适合云层的平面形状。
float valueNoise2(vec2 p)
{
    vec2 i = floor(p);  // 格子角点。
    vec2 f = fract(p);  // 格内位置。
    f = f * f * (3.0 - 2.0 * f);  // 平滑曲线。
    float a = hash12(i);  // 四个角。
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);  // 双线性插值。
}

// 二维分形叠加，供云层使用；层数与三维版本一致，但每次少一半哈希。
// 每层偏移不同常数，避免不同频率的格子边界重叠成网格。
float fbm2(vec2 p, int octaves)
{
    float sum = 0.0;  // 累加结果。
    float amplitude = 0.5;  // 当前层权重。
    for (int i = 0; i < octaves; i++)  // 固定层数。
    {
        sum += valueNoise2(p) * amplitude;  // 当前层。
        p = p * 2.03 + vec2(17.0, 31.0);  // 频率翻倍并偏移。
        amplitude *= 0.5;  // 权重减半。
    }
    return sum;  // 零到一附近。
}

// 分形叠加：每层频率翻倍、权重减半，得到云和山丘的自然起伏。
float fbm(vec3 p, int octaves)
{
    float sum = 0.0;  // 累加结果。
    float amplitude = 0.5;  // 当前层权重。
    for (int i = 0; i < octaves; i++)  // 层数由调用方控制，避免循环上限不确定。
    {
        sum += valueNoise(p) * amplitude;  // 加入当前层。
        p = p * 2.03 + vec3(17.0, 9.0, 31.0);  // 频率翻倍并偏移，减少层间重合。
        amplitude *= 0.5;  // 高层权重减半。
    }
    return sum;  // 结果大致在零到一之间。
}
