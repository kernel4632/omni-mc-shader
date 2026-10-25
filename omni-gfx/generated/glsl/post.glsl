/*
生成文件：后期模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库后期模块：泛光降采样与模糊、三次升采样、亮度曲线、暗角、颗粒、景深与测光统计。
调用位置：任何需要多级泛光、景深或最终画面处理的程序；Minecraft 光影由 `/omni-gfx/post.glsl` 引入。
可复制示例：
    `vec3 c = ogxBloomDownsample(source, uv, texel);` 十三样本降采样。
    `vec3 c = ogxBloomChainCopy(chain, uv, size);` 链上某级原样拷贝。
    `vec3 b = ogxAxialGaussianBlur(source, uv, scale, origin, size, axis, 0.12, 6.0, texel);` 一维高斯。
    `float r = ogxCocRadius(focus, depth, aperture);` 薄透镜弥散圆半径。
    `float avg = ogxExposureTileAverage(sceneTexture, params);` 加权平均亮度。
设计原因与取舍：
    纹理、像素大小、子图范围与模糊参数全部由调用方传入，库不读取引擎画面或屏幕尺寸。
    伽马编码沿用管线的四次方根近似，保证与原程序相同的亮度；五级泛光的子图排布属于宿主布局，
    仍留在 `shaders/gfx/post.glsl` 的组合函数里，这里只提供每一级的核与统计公式。
*/
#ifndef OGX_POST_INCLUDED
#define OGX_POST_INCLUDED

// 亮度权重、四次方根编码与区间重映射来自数学模块。
#include "/omni-gfx/math.glsl"
// 十三样本降采样：中心小、四角大，权重和为四，输出乘四分之一保持亮度。
vec3 ogxBloomDownsample(sampler2D source, vec2 coord, vec2 texel)
{
    vec3 blur = ogxCurveToLinear3(textureLod(source, coord, 0.0).rgb) * 0.125; // 中心样本。
    blur += ogxCurveToLinear3(textureLod(source, coord + vec2(texel.x, texel.y), 0.0).rgb) * 0.5; // 右下对角。
    blur += ogxCurveToLinear3(textureLod(source, coord + vec2(texel.x, -texel.y), 0.0).rgb) * 0.5; // 右上对角。
    blur += ogxCurveToLinear3(textureLod(source, coord + vec2(-texel.x, texel.y), 0.0).rgb) * 0.5; // 左下对角。
    blur += ogxCurveToLinear3(textureLod(source, coord + vec2(-texel.x, -texel.y), 0.0).rgb) * 0.5; // 左上对角。
    blur += ogxCurveToLinear3(textureLod(source, coord + 2.0 * vec2(texel.x, 0.0), 0.0).rgb) * 0.25; // 右两像素。
    blur += ogxCurveToLinear3(textureLod(source, coord + 2.0 * vec2(0.0, texel.y), 0.0).rgb) * 0.25; // 上两像素。
    blur += ogxCurveToLinear3(textureLod(source, coord + 2.0 * vec2(-texel.x, 0.0), 0.0).rgb) * 0.25; // 左两像素。
    blur += ogxCurveToLinear3(textureLod(source, coord + 2.0 * vec2(0.0, -texel.y), 0.0).rgb) * 0.25; // 下两像素。
    blur += ogxCurveToLinear3(textureLod(source, coord + 2.0 * vec2(texel.x, texel.y), 0.0).rgb) * 0.125; // 远处右下。
    blur += ogxCurveToLinear3(textureLod(source, coord + 2.0 * vec2(texel.x, -texel.y), 0.0).rgb) * 0.125; // 远处右上。
    blur += ogxCurveToLinear3(textureLod(source, coord + 2.0 * vec2(-texel.x, texel.y), 0.0).rgb) * 0.125; // 远处左下。
    blur += ogxCurveToLinear3(textureLod(source, coord + 2.0 * vec2(-texel.x, -texel.y), 0.0).rgb) * 0.125; // 远处左上。
    return ogxLinearToCurve3(blur * 0.25); // 权重和为四，乘四分之一保持亮度。
}

// 泛光链某一级的原样拷贝：坐标夹在这级子图范围里，零号层级读取后换回线性。
// 为什么单独成一个函数：链上第二级的边界判断由宿主决定，但“夹紧后读一次”是纯计算，
// 原程序在每个方向上各写一遍，迁进库后只保留一份。
vec3 ogxBloomChainCopy(sampler2D chain, vec2 local, vec2 originSize)
{
    vec2 coord = clamp(local, vec2(0.0), originSize); // 先夹紧，再把结果交给取样。
    return ogxCurveToLinear3(textureLod(chain, coord, 0.0).rgb); // 零号层级读取后换回线性。
}

// 沿一个方向做长条高斯，横竖各一次等价于二维高斯，样本数从平方降到线性。
vec3 ogxAxialGaussianBlur(sampler2D source, vec2 coord, vec2 coordScale, float sampleOrigin, vec2 sampleSize, vec2 axis,
    float alpha, float steps, vec2 texel)
{
    vec3 blur = vec3(0.0); // 累积颜色。
    float weights = 0.0; // 累积权重。
    for (float i = -steps; i <= steps; i++) // 从负步长到正步长。
    {
        float sampleWeight = exp2(-i * i * alpha * 5.77); // 高斯权重。
        vec2 sampleCoord = coord + axis / coordScale * texel * i * 2.0; // 当前方向的取样坐标。
        vec2 original = sampleCoord; // 记录原始坐标，用来判断是否越界。
        sampleCoord = clamp(sampleCoord, vec2(sampleOrigin, 0.0), vec2(sampleOrigin + sampleSize.x, sampleSize.y)); // 夹在当前级范围。
        sampleWeight *= float(ogxEqual(original, sampleCoord)) + 1e-20; // 被夹过的样本不参与。
        sampleCoord *= coordScale; // 还原成读取该级的坐标。
        blur += ogxCurveToLinear3(textureLod(source, sampleCoord, 0.0).rgb) * sampleWeight; // 累加样本。
        weights += sampleWeight; // 累加权重。
    }
    return blur / weights; // 归一化，样本少时亮度不变。
}

// 三次升采样：四次双线性采样合成十六像素的三次模糊。
vec4 ogxBloomBicubic(sampler2D source, vec2 coord, vec2 texSize)
{
    vec2 texel = 1.0 / texSize; // 一个像素的坐标大小。
    coord = coord * texSize - 0.5; // 换成以像素中心为原点。
    vec2 p = floor(coord); // 整数像素。
    vec2 f = coord - p; // 小数偏移。
    vec2 ff = f * f; // 偏移平方。
    vec4 w0; // 前两个权重。
    vec4 w1; // 后两个权重。
    w0.xz = 1.0 - f; w0.xz *= w0.xz * w0.xz; // 第一个权重。
    w1.yw = ff * f; // 第四个权重。
    w1.xz = 3.0 * w1.yw + 4.0 - 6.0 * ff; // 第三个权重。
    w0.yw = 6.0 - w1.xz - w1.yw - w0.xz; // 第二个权重。
    vec4 s = w0 + w1; // 每对权重和。
    vec4 c = p.xxyy + vec2(-0.5, 1.5).xyxy + w1 / s; // 合并采样位置。
    c *= texel.xxyy; // 换回零到一坐标。
    vec2 m = s.xz / (s.xz + s.yw); // 两次采样的混合比例。
    return mix(mix(textureLod(source, vec2(c.y, c.w), 0.0), textureLod(source, vec2(c.x, c.w), 0.0), m.x),
                mix(textureLod(source, vec2(c.y, c.z), 0.0), textureLod(source, vec2(c.x, c.z), 0.0), m.x), m.y); // 四次采样合成模糊。
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
vec3 ogxLuminanceCurve(vec3 color, float lower, float upper)
{
    color.r += lower * ogxLowerCurve(color.r) + upper * ogxUpperCurve(color.r); // 红通道。
    color.g += lower * ogxLowerCurve(color.g) + upper * ogxUpperCurve(color.g); // 绿通道。
    color.b += lower * ogxLowerCurve(color.b) + upper * ogxUpperCurve(color.b); // 蓝通道。
    return color;
}

// 把三个通道归一化成染色方向；接近零时返回零，避免除零。
vec3 ogxGradeTarget(float red, float green, float blue)
{
    vec3 target = vec3(red, green, blue); // 原始目标向量。
    return length(target) < 0.001 ? vec3(0.0) : normalize(target); // 太短就没有方向。
}

// 暗角：按到画面中心的距离压暗四角，圆度控制椭圆与圆形之间的形状。
float ogxVignette(vec2 coord, float falloff, float roundness, float aspect)
{
    vec2 p = coord * 2.0 - 1.0; // 转负一到一。
    p.x *= mix(1.0, aspect, roundness); // 按圆度修正横坐标。
    float rf = dot(p, p) * falloff * falloff + 1.0; // 距离平方乘强度。
    return 1.0 / (rf * rf); // 二次衰减。
}

// 胶片颗粒：把屏幕坐标与时间合成种子，折成一个正负各半的细噪点加在颜色上。
vec3 ogxFilmGrain(vec3 color, vec2 coord, float time, float strength)
{
    float seed = (coord.x + 4.0) * (coord.y + 4.0) * (time * 10.0); // 屏幕坐标与时间合成种子，时间项让它逐帧变化。
    float flicker = ogxMod((ogxMod(seed, 13.0) + 1.0) * (ogxMod(seed, 123.0) + 1.0), 0.01) - 0.005; // 两次取模相乘再折叠成一个很小的数。
    return color + vec3(flicker) * strength; // 三个通道同量叠加，颗粒不改变颜色比例。
}

// 弥散圆半径：按薄透镜公式估算一个点离对焦平面越远时散焦多大。
float ogxCocRadius(float focus, float depth, float aperture)
{
    return abs(aperture * (depth - focus) / (depth * focus)); // 薄透镜近似。
}

// 景深镜头倍数：焦距平方乘口径倍数，焦距与光圈取基准值时正好为一。
float ogxDofLensFactor(float focalLength, float aperture, float referenceFocal, float referenceAperture)
{
    float focalRatio = focalLength / referenceFocal; // 焦距相对基准的倍数，越长越大。
    float apertureRatio = referenceAperture / aperture; // f 值越小口径越大，取倒数表示反比。
    return focalRatio * focalRatio * apertureRatio; // 焦距平方乘口径倍数，得到模糊倍数。
}

// 米制距离换回非线性屏幕深度；景深写回下界历史时需要这个反向换算。
float ogxScreenDepthFromLinearDepth(float depth, mat4 projectionInverse)
{
    depth = (1.0 / depth - projectionInverse[3][3]) / projectionInverse[2][3]; // 解出负一到一的深度。
    return depth * 0.5 + 0.5; // 再转回零到一。
}

// 读一个坐标的米制深度；`useDh` 为真且近景没有几何时改读远景深度，再统一到近景尺度。
// 为什么把下限夹在换米制之前：近处深度趋近于零时薄透镜公式会爆炸，先夹屏幕深度最稳。
float ogxDofLinearDepth(vec2 coord, sampler2D depthTexture, sampler2D dhDepthTexture, mat4 projectionInverse,
    mat4 dhProjectionInverse, bool useDh)
{
    float depth = textureLod(depthTexture, coord, 0.0).x; // 读含半透明的近景深度。
    if (useDh && depth == 1.0) // 只有启用远景且近景是天空时才改读远景。
    {
        float dhDepth = textureLod(dhDepthTexture, coord, 0.0).x; // 读远景深度。
        float meters = 1.0 / ((dhDepth * 2.0 - 1.0) * dhProjectionInverse[2][3] + dhProjectionInverse[3][3]); // 远景深度换米制。
        depth = (1.0 / meters - projectionInverse[3][3]) / projectionInverse[2][3]; // 米制换到近景投影的负一到一深度。
        depth = clamp(depth * 0.5 + 0.5, 0.0, 1.0); // 转回零到一并夹紧。
    }
    depth = max(depth, 0.875); // 近处下限，避免对焦距离趋近零时弥散爆炸。
    return 1.0 / ((depth * 2.0 - 1.0) * projectionInverse[2][3] + projectionInverse[3][3]); // 换成米制距离。
}

// 前景弥散范围：在螺旋上找更近且弥散更大的样本，把它们的弥散并进当前点。
// 输入是当前点、焦距、模糊量、投影缩放、镜头倍数、最大弥散、画面比例与搜索次数；输出归一化弥散范围。
float ogxDofCocSpread(vec2 coord, sampler2D depthTexture, sampler2D dhDepthTexture, mat4 projectionInverse,
    mat4 dhProjectionInverse, bool useDh, float focus, float blur, float projectionScale, float lensFactor,
    float maxCoc, float aspect, int steps, vec2 noise)
{
    float cocRadiusfactor = blur * projectionScale * lensFactor; // 口径系数：模糊量乘投影缩放与镜头倍数。
    float rMaxCoc = 1.0 / maxCoc; // 最大弥散的倒数，用来归一化。
    float rAspect = 1.0 / aspect; // 宽高比倒数，让椭圆散景在像素上是圆的。
    float currDepth = ogxDofLinearDepth(coord, depthTexture, dhDepthTexture, projectionInverse, dhProjectionInverse, useDh); // 当前点米制深度。
    float currCoc = ogxCocRadius(focus, currDepth, cocRadiusfactor); // 当前点弥散半径。
    float startRadius = currCoc * rMaxCoc; // 当前弥散占最大值的比例。
    startRadius *= startRadius; // 平方，让搜索从中心附近开始。
    float spreadCoc = currCoc; // 弥散范围初值为当前点。
    float rSteps = 1.0 / float(steps); // 步数倒数。
    float angle = noise.x * 6.28318530718; // 起始角由噪声给出，避免固定图案。
    vec2 rot = vec2(cos(angle), sin(angle)); // 起始方向。
    for (int i = 0; i < steps; i++) // 螺旋逐点搜索。
    {
        rot = vec2(-0.737368878 * rot.x + 0.675490294 * rot.y, -0.675490294 * rot.x - 0.737368878 * rot.y); // 每步旋转黄金角。
        float sampleRadius = sqrt(startRadius + (float(i) + noise.y) * (1.0 - startRadius) * rSteps) * maxCoc; // 这个样本的半径。
        vec2 sampleOffset = rot * sampleRadius; // 屏幕偏移。
        sampleOffset.x *= rAspect; // 按宽高比修正成圆。
        float sampleDepth = ogxDofLinearDepth(coord + sampleOffset, depthTexture, dhDepthTexture, projectionInverse, dhProjectionInverse, useDh); // 样本深度。
        float sampleCoc = ogxCocRadius(focus, sampleDepth, cocRadiusfactor); // 样本弥散。
        if (sampleCoc >= sampleRadius && sampleDepth <= currDepth) // 更近且弥散够大才并进来。
        {
            spreadCoc = max(spreadCoc, sampleCoc);
        }
    }
    return min(spreadCoc, maxCoc) * rMaxCoc; // 夹到最大值并归一化。
}

// 景深散焦：按存下来的弥散范围在螺旋上取样，让更近且弥散够大的样本散到当前像素上。
// `storeDepth` 为真时把散焦后的深度一起写进透明度，供下界历史使用；屏幕深度由调用方投影矩阵换算。
vec4 ogxDepthOfField(vec2 coord, sampler2D colorTexture, sampler2D depthTexture, sampler2D dhDepthTexture,
    mat4 projectionInverse, mat4 dhProjectionInverse, bool useDh, float focus, float blur, float projectionScale,
    float lensFactor, float maxCoc, vec2 texel, float aspect, int quality, bool catEye, float catEyeMidpoint,
    float catEyeStrength, float anamorphic, float dispersion, bool storeDepth, vec2 noise)
{
    float cocRadiusfactor = blur * projectionScale * lensFactor; // 口径系数，与弥散统计共用同一换算。
    float minCoc = 0.5641895835 * texel.y; // 一个像素大小的最小弥散，避免零半径时除零。
    float rAspect = 1.0 / aspect; // 宽高比倒数。
    float currDepth = ogxDofLinearDepth(coord, depthTexture, dhDepthTexture, projectionInverse, dhProjectionInverse, useDh); // 当前点深度。
    float currCoc = ogxCocRadius(focus, currDepth, cocRadiusfactor); // 当前点弥散。
    currCoc = clamp(currCoc, minCoc, maxCoc); // 夹在最小与最大之间。
    vec4 currData = textureLod(colorTexture, coord, 0.0); // 当前点的曲线编码颜色与弥散范围。
    float spreadCoc = currData.a * maxCoc; // 把存下来的范围还原成半径。
    float centerWeight = spreadCoc * spreadCoc - spreadCoc + 1.0; // 中心权重多项式。
    centerWeight = mix(centerWeight, 1e-20, pow(currCoc / spreadCoc, 4.0)); // 当前点很清晰时把它自己压到极小。
    vec2 catEyeOffset = vec2(0.0); // 猫眼裁剪半径；关闭时保持零。
    if (catEye) // 只有开启猫眼效应才算裁剪。
    {
        catEyeOffset = coord * 2.0 - 1.0; // 从中心指向当前点。
        catEyeOffset.x *= aspect; // 按宽高比修正成圆。
        float catEyeDist = length(catEyeOffset); // 到中心的距离。
        catEyeDist = max(catEyeDist - catEyeMidpoint, 0.0); // 超过中点才开始裁剪。
        catEyeDist *= spreadCoc * catEyeStrength; // 按弥散与强度缩放。
        catEyeOffset = normalize(catEyeOffset) * catEyeDist; // 得到裁剪半径。
    }
    vec3 dof = vec3(0.0); // 散焦进来的颜色累加。
    float weights = 0.0; // 样本权重累加。
    vec3 selfColor = ogxCurveToLinear3(currData.rgb) * 1e-20; // 当前点自贡献初值极小。
    float selfSamples = 1e-20; // 自计入样本数初值极小。
    float selfWeights = 0.0; // 被拒绝样本在中心上的权重累加。
    float blendedDepth = 0.0; // 散焦后的深度累加。
    float selfDepth = currDepth * 1e-20; // 当前点自计入深度初值极小。
    float rSteps = 1.0 / float(quality); // 步数倒数。
    float angle = noise.x * 6.28318530718; // 起始角。
    vec2 rot = vec2(cos(angle), sin(angle)); // 起始方向。
    for (int i = 0; i < quality; i++) // 螺旋采样。
    {
        rot = vec2(-0.737368878 * rot.x + 0.675490294 * rot.y, -0.675490294 * rot.x - 0.737368878 * rot.y); // 每步旋转黄金角。
        float sampleRadius = sqrt((float(i) + noise.y) * rSteps) * spreadCoc; // 样本半径。
        vec2 sampleOffset = rot * sampleRadius; // 屏幕偏移。
        if (catEye && distance(catEyeOffset, sampleOffset) > spreadCoc) // 超出猫眼裁剪半径就不采。
        {
            continue;
        }
        sampleOffset.x *= rAspect * anamorphic; // 按宽高比修正后再按变形比横向拉伸。
        vec2 sampleCoord = coord + sampleOffset; // 样本坐标。
        float sampleDepth = ogxDofLinearDepth(sampleCoord, depthTexture, dhDepthTexture, projectionInverse, dhProjectionInverse, useDh); // 样本深度。
        float sampleCoc = ogxCocRadius(focus, sampleDepth, cocRadiusfactor); // 样本弥散。
        sampleCoc = clamp(sampleCoc, minCoc, maxCoc); // 夹到范围。
        vec3 sampleColor; // 样本线性颜色。
        if (dispersion != 1.0) // 色散开启时红蓝通道沿到中心的方向错开。
        {
            vec2 dispersionOffset = (coord - 0.5) * sampleRadius * (dispersion - 1.0); // 错开量随半径与到中心距离增大。
            sampleColor.r = ogxCurveToLinear(textureLod(colorTexture, sampleCoord + dispersionOffset, 0.0).r); // 红通道向外。
            sampleColor.g = ogxCurveToLinear(textureLod(colorTexture, sampleCoord, 0.0).g); // 绿通道不动。
            sampleColor.b = ogxCurveToLinear(textureLod(colorTexture, sampleCoord - dispersionOffset, 0.0).b); // 蓝通道向内。
        }
        else // 默认无色散只取一次样本。
        {
            sampleColor = ogxCurveToLinear3(textureLod(colorTexture, sampleCoord, 0.0).rgb); // 样本线性颜色。
        }
        float sampleWeight = max(1.0, currCoc / sampleCoc); // 近处前方样本权重更高。
        sampleWeight *= sampleWeight; // 平方加强。
        bool isSelfSample = currCoc >= sampleRadius && sampleDepth >= currDepth; // 样本属于当前点自己。
        bool isBlurredSample = sampleCoc >= sampleRadius && sampleDepth < currDepth; // 更近且弥散够大，散焦进来。
        if (isSelfSample) // 属于当前点自己。
        {
            selfColor += sampleColor; // 记为自贡献。
            selfSamples += 1.0; // 自贡献样本数。
        }
        else if (isBlurredSample) // 散焦进来。
        {
            dof += sampleColor * sampleWeight; // 累加散焦颜色。
            weights += sampleWeight; // 累加权重。
        }
        else // 不满足条件，记进中心权重。
        {
            selfWeights += centerWeight; // 累加中心权重。
        }
        if (isSelfSample) // 自己的样本累加深度。
        {
            selfDepth += sampleDepth;
        }
        else if (isBlurredSample) // 散焦样本按权重累加深度。
        {
            blendedDepth += sampleDepth * sampleWeight;
        }
    }
    dof += selfColor * (1.0 + selfWeights / selfSamples); // 把自贡献按被拒绝样本的补偿加回来。
    dof /= weights + selfSamples + selfWeights; // 归一化。
    if (!storeDepth) // 主世界与末地不写深度。
    {
        return vec4(ogxLinearToCurve3(dof), 0.0);
    }
    blendedDepth += selfDepth * (1.0 + selfWeights / selfSamples); // 下界把深度按同一套补偿。
    blendedDepth /= weights + selfSamples + selfWeights; // 归一化深度。
    return vec4(ogxLinearToCurve3(dof), ogxScreenDepthFromLinearDepth(blendedDepth, projectionInverse)); // 返回颜色与换回的屏幕深度。
}

// 相机动态模糊：沿两帧之间的屏幕位移，在历史画面上取一串样本求平均。
// 为什么只做相机运动：没有实体速度缓冲，硬算会把静止物体也拖出鬼影，所以只处理整屏位移。
vec3 ogxMotionBlur(sampler2D colorTexture, vec2 coord, ivec2 texel, vec2 pixel, vec2 velocity,
    float shutterAngle, int quality, bool dither)
{
    if (length(velocity) < 5e-7) // 位移极小说明相机没动，直接取当前画面。
    {
        return ogxCurveToLinear3(texelFetch(colorTexture, texel, 0).rgb);
    }
    float shutter = shutterAngle / 720.0; // 快门角换算成拖影长度。
    velocity = clamp(velocity * shutter, vec2(-0.1), vec2(0.1)); // 限制单帧拖影上限。
    float steps = float(quality); // 一侧的采样步数。
    float samples = 0.0; // 有效样本计数。
    float offset = 0.0; // 采样抖动。
    if (dither) // 交错梯度噪声打散条纹。
    {
        offset = ogxInterleavedGradientNoise(pixel);
    }
    vec3 color = vec3(0.0); // 输出颜色。
    for (float i = -steps; i <= steps; i++) // 沿快门方向对称取样。
    {
        vec2 sampleCoord = coord + velocity / (steps + 1.0) * (i + offset); // 这个样本的坐标。
        if (ogxEqual(ogxSaturate(sampleCoord), sampleCoord)) // 坐标在画面内才采。
        {
            color += ogxCurveToLinear3(textureLod(colorTexture, sampleCoord, 0.0).rgb); // 累加历史颜色。
            samples++; // 计数。
        }
    }
    return color / samples; // 按有效样本数平均。
}

// 自动曝光分块统计的参数：屏幕尺寸、块大小、测光方式与亮度计权都由调用方给出。
// 字段名沿用光影侧写法，适配层因此只需要一次类型别名，不产生结构体拷贝。
struct OgxExposureParams
{
    vec2 screen_size; // 画面像素尺寸。
    vec2 pixel_size; // 一个像素在零到一坐标里的大小。
    int lod; // 多级纹理层级，决定一块覆盖多少像素。
    float luma_scale; // 管线亮度换算系数。
    float average; // 用一张粗样本估出的整体亮度，供亮度计权使用。
    int mode; // 测光方式：零默认、一中心权重、二只看中心、三全屏平均。
    int luminance_mode; // 亮度计权方式：零关闭，一到四对应四种曲线。
    float luminance_strength; // 亮度计权的强度。
    bool end_dimension; // 是否末地，末地默认测光不看中心。
    bool nether; // 是否下界，亮度计权在下界用固定指数。
    bool cave_mode; // 是否洞穴模式，洞穴按偏离整体亮度计权。
    bool overworld; // 是否主世界，亮度计权的指数范围与末地不同。
};

// 返回加权平均亮度，单位与输入画面一致；调用方再乘曝光输出系数并编码。
// 为什么分块而不是逐像素：逐像素太贵；分块加计权既便宜又能得到接近整屏的平均亮度。
float ogxExposureTileAverage(sampler2D sceneTexture, OgxExposureParams params)
{
    float tileScale = exp2(float(params.lod)); // 一个块覆盖多少像素。
    vec2 tileCount = floor(params.screen_size / tileScale); // 每行每列有多少块。
    vec2 tileCenter = tileCount * 0.5; // 块网格的中心。
    float exposure = 0.0; // 加权亮度累加。
    float weights = 0.0; // 权重累加。
    for (int x = 0; x < int(tileCount.x); x++) // 逐列遍历块。
    {
        for (int y = 0; y < int(tileCount.y); y++) // 逐行遍历块。
        {
            float tileExposure = ogxLuminance(ogxCurveToLinear3(texelFetch(sceneTexture, ivec2(x, y), params.lod).rgb)) * params.luma_scale; // 这个块的亮度。
            vec2 tileDistance = (tileCenter - vec2(x, y) + 0.5) * params.pixel_size * tileScale * 2.0; // 块中心到画面中心的屏幕距离。
            float centerDistance = length(tileDistance); // 到画面中心的距离。
            float tileWeight = 1.0; // 块权重，先给等权。
            if (params.mode == 0) // 默认测光。
            {
                tileWeight = params.end_dimension ? 1.0 : ogxRemapSaturate(centerDistance, 0.6, 0.4); // 末地等权，其他维度越靠中心越高。
            }
            else if (params.mode == 1) // 中心权重较强。
            {
                tileWeight = ogxRemapSaturate(centerDistance, 0.7, 0.0); // 中心权重曲线。
                tileWeight *= tileWeight; // 再平方，中心更突出。
            }
            else if (params.mode == 2) // 只看中心。
            {
                tileWeight = ogxRemapSaturate(centerDistance, 0.6, 0.4); // 与默认相同的曲线。
            }
            tileExposure = max(6.4e-9, tileExposure); // 避免全黑块把权重推到无穷。
            if (params.cave_mode && params.overworld) // 洞穴模式且在主世界时按偏离程度计权。
            {
                float caveWeight = params.average / tileExposure; // 相对整体亮度的比例。
                tileWeight *= pow(caveWeight, 0.7); // 越偏离整体亮度权重越大，适应洞穴。
            }
            else if (params.luminance_mode > 0) // 其他情况按亮度计权方式。
            {
                float lumaWeight = 1.0; // 相对亮度权重。
                if (params.luminance_mode == 1) // 预设一。
                {
                    lumaWeight = params.average / tileExposure; // 相对亮度。
                    if (params.nether) // 下界用固定指数。
                    {
                        lumaWeight = pow(lumaWeight, 0.7);
                    }
                    else if (params.overworld) // 主世界按整体亮度调指数。
                    {
                        lumaWeight = pow(lumaWeight, ogxRemapSaturate(params.average, 1.55e-6, 6.25e-8) * 0.7); // 暗环境更偏向亮块。
                    }
                    else // 末地指数范围不同。
                    {
                        lumaWeight = pow(lumaWeight, ogxRemapSaturate(params.average, 1.55e-6, 6.25e-8) * 0.5 + 0.2); // 末地曲线。
                    }
                }
                else if (params.luminance_mode == 2) // 预设二。
                {
                    lumaWeight = params.average / tileExposure; // 相对亮度。
                    lumaWeight = pow(lumaWeight, params.nether ? 0.7 : ogxRemapSaturate(params.average, 1.55e-6, 6.25e-8) * 0.5 + 0.2); // 下界固定，其余用较平的曲线。
                }
                else if (params.luminance_mode == 3) // 偏向暗部。
                {
                    lumaWeight = pow(params.average / tileExposure, params.luminance_strength); // 用选项给的强度。
                }
                else // 偏向高光。
                {
                    lumaWeight = pow(tileExposure / params.average, params.luminance_strength); // 比例取反。
                }
                tileWeight *= lumaWeight; // 把亮度权重乘进块权重。
            }
            exposure += tileExposure * tileWeight; // 累加加权亮度。
            weights += tileWeight; // 累加权重。
        }
    }
    return exposure / weights; // 加权平均。
}

// 镜头眩光：求一个偏移向量在桶形畸变后的方向，用于把鬼影沿弧线排列。
// 先把偏移抬到三维再绕与中心垂直的轴旋转，最后取回二维，等价于绕画面中心弯折。
vec2 ogxGlareDistOffset(vec2 uv, vec2 pxoffset, float barrel)
{
    vec2 tocenter = uv.xy; // 当前点到中心的方向。
    vec3 prep = normalize(vec3(tocenter.y, -tocenter.x, 0.0)); // 与中心方向垂直的轴。
    float angle = length(tocenter.xy) * 2.221 * barrel; // 旋转角随距离增大。
    vec3 oldoffset = vec3(pxoffset, 0.0); // 把偏移抬到三维。
    vec3 rotated = oldoffset * cos(angle) + cross(prep, oldoffset) * sin(angle) + prep * dot(prep, oldoffset) * (1.0 - cos(angle)); // 绕轴旋转。
    return rotated.xy; // 取回二维偏移。
}

// 画一个带色散的软光点：红绿蓝三个通道沿鬼影方向错开一点。
// 色散量同时改变三个通道的半径，蓝光偏得最多，边缘因此出现彩边。
vec3 ogxGlareFlare(vec2 uv, vec2 pos, float dist, float chromaOffset, float size, float barrel)
{
    pos = ogxGlareDistOffset(uv, pos, barrel); // 先对鬼影位置做桶形畸变。
    float r = max(0.01 - pow(length(uv + (dist - chromaOffset) * pos), 2.4) * (1.0 / (size * 2.0)), 0.0) * 0.85; // 红色通道。
    float g = max(0.01 - pow(length(uv + dist * pos), 2.4) * (1.0 / (size * 2.0)), 0.0) * 1.0; // 绿色通道。
    float b = max(0.01 - pow(length(uv + (dist + chromaOffset) * pos), 2.4) * (1.0 / (size * 2.0)), 0.0) * 1.5; // 蓝色通道。
    return vec3(r, g, b); // 返回带色散的光点颜色。
}

// 画一串沿鬼影方向排列的圆形光斑，颜色从暖到冷渐变。
// 越靠后的光斑越小、越暗，模拟镜头内部多次反射的能量损失。
vec3 ogxGlareOrb(vec2 uv, vec2 pos, float dist, float size, float barrel)
{
    float orbCount = 6.0; // 一组鬼影包含几个圆形光斑。
    vec3 c = vec3(0.0); // 累加结果。
    for (float i = 0.0; i < orbCount; i++) // 逐个光斑。
    {
        float j = i + 1.0; // 从一起数的序号。
        float offset = j / (j + 0.1); // 这个光斑在鬼影方向上的位置。
        float colOffset = j / orbCount * 0.5; // 颜色偏移。
        float ss = size / (j + 1.0); // 越靠后的光斑越小。
        c += ogxGlareFlare(uv, pos, dist + offset, ss * 2.0, ss, barrel) * vec3(1.0 - colOffset, 1.0, 0.5 + colOffset) * j; // 累加并染色放大。
    }
    c += ogxGlareFlare(uv, pos, dist + 0.8, 0.05, 3.0 * size, barrel) * 0.5; // 末尾再补一个大的柔和光斑。
    return c; // 返回光斑颜色。
}

// 画一个环状光环，三个通道同样做色散。
// 坐标先乘自身长度，圆点就被拉成环；分母里的二百五十控制环的锐度。
vec3 ogxGlareRing(vec2 uv, vec2 pos, float dist, float chromaOffset, float blur)
{
    vec2 uvd = uv * length(uv); // 把坐标按到中心距离放大，得到环而不是点。
    float r = max(1.0 / (1.0 + 250.0 * pow(length(uvd + (dist - chromaOffset) * pos), blur)), 0.0) * 0.8; // 红色通道。
    float g = max(1.0 / (1.0 + 250.0 * pow(length(uvd + dist * pos), blur)), 0.0) * 1.0; // 绿色通道。
    float b = max(1.0 / (1.0 + 250.0 * pow(length(uvd + (dist + chromaOffset) * pos), blur)), 0.0) * 1.5; // 蓝色通道。
    return vec3(r, g, b); // 返回光环颜色。
}

#endif
