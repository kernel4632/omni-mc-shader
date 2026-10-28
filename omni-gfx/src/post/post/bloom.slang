/*
后期子文件：泛光链拷贝、轴向高斯模糊、三次纹理放大、色调曲线与颗粒。
调用位置：由 `post/post.slang` 内联，合成阶段的泛光与调色直接调用这些入口。
可复制示例：`vec3 b = ogxBloomChainCopy(chain, local, originSize);`
设计原因与取舍：每级只做一次可复用的核，链的边界与混合由调用方决定；权重和与参考一致。
    降采样入口放在主文件，子文件只保留需要多行展开的核。
*/
// 泛光链某一级的原样拷贝：坐标夹在这级子图范围里，零号层级读取后换回线性。
// 为什么单独成一个函数：链上第二级的边界判断由宿主决定，但“夹紧后读一次”是纯计算，
// 原程序在每个方向上各写一遍，迁进库后只保留一份。
float3 ogxBloomChainCopy(Sampler2D chain, float2 local, float2 originSize)
{
    float2 coord = clamp(local, float2(0.0), originSize); // 先夹紧，再把结果交给取样。
    return ogxCurveToLinear3(chain.SampleLevel(coord, 0.0).rgb); // 零号层级读取后换回线性。
}

// 沿一个方向做长条高斯，横竖各一次等价于二维高斯，样本数从平方降到线性。
float3 ogxAxialGaussianBlur(Sampler2D source, float2 coord, float2 coordScale, float sampleOrigin, float2 sampleSize, float2 axis,
    float alpha, float steps, float2 texel)
{
    float3 blur = float3(0.0); // 累积颜色。
    float weights = 0.0; // 累积权重。
    for (float i = -steps; i <= steps; i++) // 从负步长到正步长。
    {
        float sampleWeight = exp2(-i * i * alpha * 5.77); // 高斯权重。
        float2 sampleCoord = coord + axis / coordScale * texel * i * 2.0; // 当前方向的取样坐标。
        float2 original = sampleCoord; // 记录原始坐标，用来判断是否越界。
        sampleCoord = clamp(sampleCoord, float2(sampleOrigin, 0.0), float2(sampleOrigin + sampleSize.x, sampleSize.y)); // 夹在当前级范围。
        sampleWeight *= float(ogxEqual(original, sampleCoord)) + 1e-20; // 被夹过的样本不参与。
        sampleCoord *= coordScale; // 还原成读取该级的坐标。
        blur += ogxCurveToLinear3(source.SampleLevel(sampleCoord, 0.0).rgb) * sampleWeight; // 累加样本。
        weights += sampleWeight; // 累加权重。
    }
    return blur / weights; // 归一化，样本少时亮度不变。
}

// 三次升采样：四次双线性采样合成十六像素的三次模糊。
float4 ogxBloomBicubic(Sampler2D source, float2 coord, float2 texSize)
{
    float2 texel = 1.0 / texSize; // 一个像素的坐标大小。
    coord = coord * texSize - 0.5; // 换成以像素中心为原点。
    float2 p = floor(coord); // 整数像素。
    float2 f = coord - p; // 小数偏移。
    float2 ff = f * f; // 偏移平方。
    float4 w0; // 前两个权重。
    float4 w1; // 后两个权重。
    w0.xz = 1.0 - f; w0.xz *= w0.xz * w0.xz; // 第一个权重。
    w1.yw = ff * f; // 第四个权重。
    w1.xz = 3.0 * w1.yw + 4.0 - 6.0 * ff; // 第三个权重。
    w0.yw = 6.0 - w1.xz - w1.yw - w0.xz; // 第二个权重。
    float4 s = w0 + w1; // 每对权重和。
    float4 c = p.xxyy + float2(-0.5, 1.5).xyxy + w1 / s; // 合并采样位置。
    c *= texel.xxyy; // 换回零到一坐标。
    float2 m = s.xz / (s.xz + s.yw); // 两次采样的混合比例。
    return lerp(lerp(source.SampleLevel(float2(c.y, c.w), 0.0), source.SampleLevel(float2(c.x, c.w), 0.0), m.x),
                lerp(source.SampleLevel(float2(c.y, c.z), 0.0), source.SampleLevel(float2(c.x, c.z), 0.0), m.x), m.y); // 四次采样合成模糊。
}

// 亮度曲线：暗部与亮部各一条抛物线，通道独立处理避免串色。
float ogxLowerCurve(float x)
{
    return clamp(16.0 * x * (0.5 - x) * 0.1, 0.0, 1.0); // 峰在四分之一附近。
}

// 亮部曲线：在亮端抬起一段抛物线。
float ogxUpperCurve(float x)
{
    return clamp(16.0 * (0.5 - x) * (x - 1.0) * 0.1, 0.0, 1.0); // 峰在四分之三附近。
}

// 把暗部与亮部修正同时加到三个通道，系数由调用方传入。
float3 ogxLuminanceCurve(float3 color, float lower, float upper)
{
    color.r += lower * ogxLowerCurve(color.r) + upper * ogxUpperCurve(color.r); // 红通道。
    color.g += lower * ogxLowerCurve(color.g) + upper * ogxUpperCurve(color.g); // 绿通道。
    color.b += lower * ogxLowerCurve(color.b) + upper * ogxUpperCurve(color.b); // 蓝通道。
    return color;
}

// 把三个通道归一化成染色方向；接近零时返回零，避免除零。
float3 ogxGradeTarget(float red, float green, float blue)
{
    float3 target = float3(red, green, blue); // 原始目标向量。
    return length(target) < 0.001 ? float3(0.0) : normalize(target); // 太短就没有方向。
}

// 暗角：按到画面中心的距离压暗四角，圆度控制椭圆与圆形之间的形状。
float ogxVignette(float2 coord, float falloff, float roundness, float aspect)
{
    float2 p = coord * 2.0 - 1.0; // 转负一到一。
    p.x *= lerp(1.0, aspect, roundness); // 按圆度修正横坐标。
    float rf = dot(p, p) * falloff * falloff + 1.0; // 距离平方乘强度。
    return 1.0 / (rf * rf); // 二次衰减。
}

// 胶片颗粒：把屏幕坐标与时间合成种子，折成一个正负各半的细噪点加在颜色上。
float3 ogxFilmGrain(float3 color, float2 coord, float time, float strength)
{
    float seed = (coord.x + 4.0) * (coord.y + 4.0) * (time * 10.0); // 屏幕坐标与时间合成种子，时间项让它逐帧变化。
    float flicker = ogxMod((ogxMod(seed, 13.0) + 1.0) * (ogxMod(seed, 123.0) + 1.0), 0.01) - 0.005; // 两次取模相乘再折叠成一个很小的数。
    return color + float3(flicker) * strength; // 三个通道同量叠加，颗粒不改变颜色比例。
}

// 弥散圆半径：按薄透镜公式估算一个点离对焦平面越远时散焦多大。

// 浮点输出抖动：按目标格式的尾数位数，把三角噪声缩放到相邻两个可表示值之间。
// 为什么按指数缩放：浮点数的间隔随数值变大，固定步长会在大值处看不见、小值处过重。
float3 ogxDitherFloat(float3 color, float2 coord, float time, float3 mantissaBits)
{
    float dither = ogxTriangleNoise(coord, time);
    float3 exponent = floor(log2(max(color, float3(1e-20))));
    return color + dither * exp2(-mantissaBits) * exp2(exponent);
}

// 整数输出抖动：按目标格式的小数位数取固定步长，适合十六位或十位定点的中间画面。
float3 ogxDitherFixed(float3 color, float2 coord, float time, float bits)
{
    return color + ogxTriangleNoise(coord, time) * exp2(bits); // bits 用参考的负指数写法，例如 -8。
}

