/*
生成文件：视差模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中按效果分文件夹，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库视差模块：在地表材质的高度图上沿视线找可见交点，并算视差自阴影与法线。
调用位置：任何使用方块图集高度图做视差的几何片元程序；Minecraft 光影由
    `/omni-gfx/parallax.glsl` 引入，`rendering/parallax.glsl` 只保留选项换算。
可复制示例：调用 ogxParallaxSmooth 传入坐标、切线基与画质参数，返回最终采样像素。
设计原因与取舍：
    方块图集、高度图、切线基、视线位置、分辨率与全部画质参数由调用方传入，库不读取任何引擎状态。
    平滑模式用双线性高度采样加二分细化，锐利模式逐像素穿越图块；两种外观差别明显，所以保留两套函数。
    高度为零表示没有视差数据，统一补成完整高度，避免出现空洞；这一条在所有读取高度的地方都要执行。
*/
#ifndef OGX_PARALLAX_INCLUDED
#define OGX_PARALLAX_INCLUDED

// 数学模块提供法线解码、夹紧与位运算近似；采样模块提供时间蓝噪声。
#include "/omni-gfx/math.glsl"
#include "/omni-gfx/sampling.glsl"
// 把向量转到切线空间：显式按切线基的三个列向量点乘。
// 为什么不用矩阵乘：Slang 与 GLSL 的行列顺序不同，写成矩阵会在两个后端得到不同结果；
// 三个点乘在两种语言里语义完全相同，也不会触发后端的矩阵类型限制。
vec3 ogxParallaxToTangent(vec3 vector, vec3 tangent, vec3 bitangent, vec3 normal)
{
    return vec3(dot(vector, tangent), dot(vector, bitangent), dot(vector, normal)); // 每一列就是一个基向量。
}

// 双线性高度采样：坐标以像素为单位，图块左上角与分辨率掩码决定回绕范围。
// 参考把高度存在法线贴图的 alpha 通道；高度为零表示该像素没有视差数据，补成完整高度。
// 采样器放在参数表最后：参考用全局 `normals`，通用库必须由调用方显式给出图集。
float ogxBilinearHeightSample(vec2 coord, ivec2 tilesBaseTexel, float textureResolution, int iTextureResolution, bool isBlock, sampler2D normals)
{
    ivec2 texelX = ivec2(floor(coord)); // 左下角像素。
    ivec2 texelW = texelX + 1; // 右上角像素。
    vec2 f = coord - vec2(texelX); // 到左下角的小数偏移。
    if (isBlock) // 方块图集按图块回绕。
    {
        texelX = tilesBaseTexel + (texelX & iTextureResolution); // 左下角回绕到本图块内。
        texelW = tilesBaseTexel + (texelW & iTextureResolution); // 右上角同理。
    }
    vec4 sh = vec4(texelFetch(normals, texelX, 0).a, // 左下角高度。
        texelFetch(normals, ivec2(texelW.x, texelX.y), 0).a, // 右下角高度。
        texelFetch(normals, ivec2(texelX.x, texelW.y), 0).a, // 左上角高度。
        texelFetch(normals, texelW, 0).a); // 右上角高度。
    sh += OGX_CLAMP01(1.0 - sh * 1e20); // 高度为零表示没有视差数据，补成完整高度，避免出现空洞。
    return mix(mix(sh.x, sh.y, f.x), // 先沿横轴插值两对。
        mix(sh.z, sh.w, f.x), // 再沿横轴插值另外两对。
        f.y); // 最后沿纵轴插值得到高度。
}

// 用高度差直接生成法线：参考默认取「由高度生成法线」这一支，中心差分出一个三轴法线。
// 采样器与深度放在最后，图集与分辨率由调用方给出，函数本身不读引擎状态。
vec3 ogxHeightBasedNormal(vec2 coord, ivec2 tilesBaseTexel, float textureResolution, int iTextureResolution, bool isBlock, sampler2D normals, float depth)
{
    coord -= 0.5; // 把坐标移到像素中心。
    ivec2 texelX = ivec2(floor(coord)); // 左下角像素。
    ivec2 texelW = texelX + 1; // 右上角像素。
    vec2 f = coord - vec2(texelX); // 小数偏移。
    if (isBlock) // 方块图集按图块回绕。
    {
        texelX = tilesBaseTexel + (texelX & iTextureResolution); // 左下角回绕。
        texelW = tilesBaseTexel + (texelW & iTextureResolution); // 右上角同理。
    }
    vec4 sh = vec4(texelFetch(normals, texelX, 0).a, // 四角高度。
        texelFetch(normals, ivec2(texelW.x, texelX.y), 0).a,
        texelFetch(normals, ivec2(texelX.x, texelW.y), 0).a,
        texelFetch(normals, texelW, 0).a);
    sh.w = sh.y + sh.z - sh.x - sh.w; // 把四角合成一个中心差分量。
    return vec3(sh.w * f.yx + (sh.x - sh.yz), (8.0 / depth) / textureResolution); // 梯度乘深度再归一化，深度越大法线越陡。
}

// 平滑视差主函数：参考签名是坐标、切线基、光方向、纹理导数与两个输出，其余输入显式追加。
// 为什么追加参数都在尾部：参考把这些量写成全局变量或宏，迁进库时必须显式接收，
// 但参考参数仍排在最前面，严格对照才能逐项核对。
// 为什么阴影抖动在库内取噪声：参考在函数体里调用蓝噪声函数，采样次数属于算法的一部分。
ivec2 ogxParallaxOcclusionMapping(vec2 coord, mat3 tbnMat, vec3 shadowVector, vec2 duv1, vec2 duv2,
    inout vec3 normalTex, inout float parallaxShadow,
    sampler2D normals, sampler2D noiseTexture, vec2 atlasSize, float textureResolution, bool isBlock,
    int quality, int refinements, int shadowQuality, float depth, bool shadowEnabled, bool taa,
    bool fadeEnabled, bool useHeightNormal, vec3 viewPos, ivec2 fragCoord, int frameCounter)
{
    vec2 atlasTiles = vec2(atlasSize) / textureResolution; // 图集里横纵各有多少个图块。
    vec2 duvMax = max(abs(duv1), abs(duv2)) * atlasTiles; // 纹理坐标的屏幕变化量换成图块单位。
    float fade = 1.0; // 远处淡出因子，未开淡出时不参与。
    if (fadeEnabled) fade = OGX_CLAMP01(pow(max(duvMax.x, duvMax.y), -0.1) * (1.0 / 1.4)); // 像素越小越淡出，避免远处闪烁。
    vec2 tilesBaseCoord = floor(coord * atlasTiles); // 当前坐标落在哪个图块。
    ivec2 tilesBaseTexel = ivec2(tilesBaseCoord * textureResolution); // 该图块左上角的像素坐标。
    int iTextureResolution = int(textureResolution) - 1; // 图块边长减一，用作回绕掩码。
    vec3 parallaxTexelCoord = vec3(coord * atlasSize, 1.0); // 换成图集像素坐标并把深度放到一。
    float sampleHeight = ogxBilinearHeightSample(parallaxTexelCoord.xy - 0.5, tilesBaseTexel, textureResolution, iTextureResolution, isBlock, normals); // 先读起始高度。
    if (sampleHeight > 0.0 && sampleHeight < 1.0) // 只有处在表面内部的像素才需要偏移。
    {
        parallaxTexelCoord.xy -= 0.5; // 坐标移到像素中心。
        vec3 viewVector = ogxParallaxToTangent(normalize(viewPos), tbnMat[0], tbnMat[1], tbnMat[2]); // 视线方向转到切线空间。
        viewVector /= -viewVector.z; // 归一化到单位深度步长。
        vec3 stepDir = viewVector / float(quality); // 每一步的方向。
        stepDir.xy *= textureResolution * depth * 0.25; // 横向步长按图块尺寸与深度缩放。
        float stepDelta = 2.0 / float(quality); // 每一步增加的步长，和参考同一个分配。
        float stepLength = stepDelta; // 逐步加深的初始步长。
        for (int i = 0; i < quality; i++, stepLength += stepDelta) // 线性步进找交点。
        {
            parallaxTexelCoord += stepDir * stepLength; // 前进一小步。
            sampleHeight = ogxBilinearHeightSample(parallaxTexelCoord.xy, tilesBaseTexel, textureResolution, iTextureResolution, isBlock, normals); // 读这一步的高度。
            if (sampleHeight > parallaxTexelCoord.z) break; // 表面高度超过步进深度就找到了交点。
        }
        for (int i = 0; i < refinements; i++) // 二分细化交点。
        {
            if (sampleHeight > parallaxTexelCoord.z) // 越过交点就回退半步。
            {
                parallaxTexelCoord -= stepDir * stepLength; // 回退。
                stepLength *= 0.5; // 步长减半。
            }
            parallaxTexelCoord += stepDir * stepLength; // 再前进一个更小的步。
            sampleHeight = ogxBilinearHeightSample(parallaxTexelCoord.xy, tilesBaseTexel, textureResolution, iTextureResolution, isBlock, normals); // 读高度。
        }
        if (sampleHeight <= parallaxTexelCoord.z) parallaxTexelCoord += stepDir * stepLength * 2.0; // 最后仍未越界就多走两步，避免停在表面下。
        if (shadowEnabled && parallaxShadow > 0.0) // 只有原先允许受光的像素才算阴影。
        {
            shadowVector = ogxParallaxToTangent(shadowVector, tbnMat[0], tbnMat[1], tbnMat[2]); // 阳光方向转到切线空间。
            shadowVector /= shadowVector.z * 0.9 + 0.1; // 归一化到单位深度步长，避免水平方向过大。
            vec3 shadowTexelCoord = parallaxTexelCoord; // 从交点出发。
            vec3 stepSize = shadowVector / float(shadowQuality); // 阴影步进方向。
            stepSize.xy *= textureResolution * depth * 0.25; // 横向步长按图块与深度缩放。
            if (taa) shadowTexelCoord += stepSize * ogxBlueNoiseTemporal(noiseTexture, fragCoord, frameCounter).x; // 开时间抗锯齿时用蓝噪声抖动起点。
            else shadowTexelCoord += stepSize; // 不开时只多走一步。
            for (int i = 0; i < shadowQuality; i++, shadowTexelCoord += stepSize) // 沿光方向步进找遮挡。
            {
                if (shadowTexelCoord.z > 1.0) break; // 超出表面顶部就不再遮挡。
                sampleHeight = ogxBilinearHeightSample(shadowTexelCoord.xy, tilesBaseTexel, textureResolution, iTextureResolution, isBlock, normals); // 读遮挡候选的高度。
                float diff = shadowTexelCoord.z - sampleHeight; // 光线高度减去表面高度，负得越多遮挡越强。
                parallaxShadow *= OGX_CLAMP01(diff * 40.0 + 1.0); // 逐步累积遮蔽。
                if (parallaxShadow < 0.003) break; // 已经足够黑就提前结束。
            }
            if (fadeEnabled) parallaxShadow = mix(1.0, parallaxShadow, fade); // 远处淡出阴影，避免闪烁。
        }
        parallaxTexelCoord.xy += 0.5; // 坐标移回像素角。
        if (useHeightNormal) normalTex = ogxHeightBasedNormal(parallaxTexelCoord.xy, tilesBaseTexel, textureResolution, iTextureResolution, isBlock, normals, depth); // 由高度场求法线。
        parallaxTexelCoord.xy = (fract(parallaxTexelCoord.xy / textureResolution) + tilesBaseCoord) * textureResolution; // 把偏移后的坐标折回原本的图块。
    }
    ivec2 parallaxTexel = ivec2(parallaxTexelCoord.xy); // 最终要采样到的像素。
    if (!useHeightNormal) normalTex = ogxDecodeNormalTex(texelFetch(normals, parallaxTexel, 0).rgb); // 不用高度法线时从法线贴图取。
    else if (fadeEnabled) normalTex = mix(vec3(0.0, 0.0, 1.0), normalTex, fade); // 远处淡出到朝外法线。
    return parallaxTexel; // 交回被遮挡后的采样像素。
}

// 旧调用形状的适配层：把切线基三轴合成矩阵，转调上面的严格实现。
// 保留这个入口是为了让渲染流程只改参数来源，不必理解库内的严格签名。
ivec2 ogxParallaxSmooth(vec2 coord, vec3 tangent, vec3 bitangent, vec3 normal, vec3 shadowVector, vec2 duv1, vec2 duv2, vec3 viewPos,
    sampler2D normals, sampler2D noiseTexture, vec2 atlasSize, float textureResolution, bool isBlock,
    float depth, int quality, int refinements, int shadowQuality, bool shadowEnabled, bool taa,
    bool fadeEnabled, ivec2 fragCoord, int frameCounter, int basedNormal, inout vec3 normalTex, inout float parallaxShadow)
{
    mat3 tbnMat = mat3(tangent, bitangent, normal); // 参考把切线基当矩阵使用，这里按列拼回去。
    return ogxParallaxOcclusionMapping(coord, tbnMat, shadowVector, duv1, duv2, normalTex, parallaxShadow,
        normals, noiseTexture, atlasSize, textureResolution, isBlock, quality, refinements, shadowQuality,
        depth, shadowEnabled, taa, fadeEnabled, basedNormal == 2, viewPos, fragCoord, frameCounter); // 默认模式不额外求高度法线。
}

// 锐利模式的命中法线处理：按「由凹凸生成法线」的取值决定是否换回贴图法线或远处淡出。
vec3 ogxParallaxHitNormal(sampler2D normals, ivec2 parallaxTexel, vec3 hitNormal, float fade,
    bool fadeEnabled, int basedNormal)
{
    if (basedNormal == 1) // 仅侧面：只有步进里命中侧面时才用视差法线。
    {
        if (fadeEnabled) // 远处淡出到贴图法线。
        {
            hitNormal = mix(ogxDecodeNormalTex(texelFetch(normals, parallaxTexel, 0).rgb), hitNormal, fade * (1.0 - hitNormal.z));
        }
        else if (hitNormal.z == 1.0) // 没命中侧面时用贴图法线。
        {
            hitNormal = ogxDecodeNormalTex(texelFetch(normals, parallaxTexel, 0).rgb);
        }
    }
    else if (basedNormal == 2 && fadeEnabled) // 全部用视差法线且需淡出时。
    {
        hitNormal = mix(vec3(0.0, 0.0, 1.0), hitNormal, fade); // 远处淡出到朝外法线。
    }
    return hitNormal; // 交回处理后的法线。
}

// 锐利视差：沿视线逐像素穿过高度图，命中后可选算自阴影与法线。
// 与平滑模式的区别是每步都跨到下一个纹素边界，边缘更硬，适合像素风材质。
ivec2 ogxParallaxSharp(vec2 coord, vec3 tangent, vec3 bitangent, vec3 normal, vec3 shadowVector, vec2 duv1, vec2 duv2, vec3 viewPos,
    sampler2D normals, vec2 atlasSize, float textureResolution, bool isBlock,
    float depth, int quality, int shadowQuality, bool shadowEnabled, bool fadeEnabled,
    int basedNormal, inout vec3 hitNormal, inout float parallaxShadow)
{
    vec2 atlasTiles = atlasSize / textureResolution; // 图集里横纵各有多少个图块。
    vec2 pixelCoord = coord * atlasSize; // 当前坐标换算成图集像素。
    ivec2 parallaxTexel = ivec2(floor(pixelCoord)); // 起始像素。
    int resolutionMask = int(textureResolution) - 1; // 图块边长减一，用作回绕掩码。
    float fade = 1.0; // 远处淡出因子，未开淡出时不参与。
    if (fadeEnabled) // 需要淡出时先算这一处的淡出因子。
    {
        vec2 duvMax = max(abs(duv1), abs(duv2)) * atlasTiles; // 纹理坐标的屏幕变化量换成图块单位。
        fade = ogxSaturate(pow(max(duvMax.x, duvMax.y), -0.4) * 0.2); // 像素越小越淡出。
    }
    float sampleHeight = texelFetch(normals, parallaxTexel, 0).a; // 起始高度。
    sampleHeight += ogxSaturate(1.0 - sampleHeight * 1e20); // 高度为零时补成完整高度。
    bool exit = false; // 是否命中了表面。
    if (sampleHeight > 0.0 && sampleHeight < 1.0) // 只有处在表面内部才穿越。
    {
        ivec2 tilesPixelBase = ivec2(floor(coord * atlasTiles) * textureResolution); // 当前图块左上角的像素。
        vec3 viewVector = ogxParallaxToTangent(normalize(viewPos), tangent, bitangent, normal); // 视线方向转到切线空间。
        vec3 stepDir = normalize(vec3(viewVector.xy * depth * textureResolution * 0.25, -viewVector.z)); // 每像素前进方向，横向按深度缩放。
        vec2 ardir = abs(1.0 / stepDir.xy); // 每走一个像素在横纵方向各需要多远。
        ivec2 sdir = (floatBitsToInt(stepDir.xy) >> 31) * 2 + 1; // 横纵方向的符号，用位运算取正负一。
        vec2 totalStep = (vec2(sdir) * (0.5 - (pixelCoord - vec2(parallaxTexel))) + 0.5) * ardir; // 到下一个像素边界的距离。
        float stepLength = 0.0; // 这一步走过的深度。
        float stepHeight = 1.0; // 这一步光线所在的高度。
        float prevStepHeight = 1.0; // 上一步高度，用于判断交点落在哪一列。
        ivec2 stepNext = ivec2(0); // 这一步往哪个方向跨像素。
        for (int i = 0; i < quality; i++) // 逐像素前进。
        {
            stepLength = min(totalStep.x, totalStep.y); // 先碰到哪一侧边界就按哪一侧走。
            stepHeight = 1.0 - stepLength * stepDir.z; // 这一步光线到达的高度。
            if (sampleHeight > stepHeight) // 表面高过光线，说明这一段遮挡了像素。
            {
                if (sampleHeight > prevStepHeight) // 交点落在上一步与这一步之间时用上一步的法线。
                {
                    hitNormal = vec3(-stepNext * sdir, 0.0); // 由跨步方向估计侧面法线。
                    sampleHeight = prevStepHeight; // 高度取上一步，便于后续阴影。
                }
                exit = true; // 标记命中。
                break; // 结束步进。
            }
            stepNext = (floatBitsToInt(vec2(stepLength) - totalStep) >> 31) + 1; // 判断这一步跨的是哪一侧。
            parallaxTexel += stepNext * sdir; // 前进到下一个像素。
            totalStep += vec2(stepNext) * ardir; // 累加边界距离。
            prevStepHeight = stepHeight; // 记下这一步高度。
            if (isBlock) parallaxTexel = tilesPixelBase + (parallaxTexel & resolutionMask); // 方块图集折回本图块。
            sampleHeight = texelFetch(normals, parallaxTexel, 0).a; // 读新像素的高度。
            sampleHeight += ogxSaturate(1.0 - sampleHeight * 1e20); // 高度为零时补成完整高度。
        }
        if (shadowEnabled) // 需要自阴影时。
        {
            vec3 shadowDir = ogxParallaxToTangent(shadowVector, tangent, bitangent, normal); // 阳光方向转到切线空间。
            float shadow = 1.0; // 阴影透过率从全透开始。
            if (dot(shadowDir, hitNormal) * parallaxShadow > 0.0 && exit) // 命中的侧面朝向阳光才需要阴影。
            {
                float currHeight = sampleHeight; // 当前高度。
                stepLength = (1.0 - currHeight) / stepDir.z; // 先走到表面顶部。
                vec2 shadowCoord2d = pixelCoord + stepLength * stepDir.xy; // 到达顶部时的像素坐标。
                ivec2 shadowTexel = ivec2(floor(shadowCoord2d)); // 取整。
                stepDir = normalize(vec3(shadowDir.xy * depth * textureResolution * 0.25, shadowDir.z)); // 换成沿光方向的前进方向。
                vec2 ardirShadow = abs(1.0 / stepDir.xy); // 每像素的边界距离。
                ivec2 sdirShadow = (floatBitsToInt(stepDir.xy) >> 31) * 2 + 1; // 方向符号。
                totalStep = (vec2(sdirShadow) * (0.5 - (shadowCoord2d - vec2(shadowTexel))) + 0.5) * ardirShadow; // 到下一像素边界的距离。
                stepNext = ivec2(0); // 复位跨步方向。
                for (int i = 0; i < shadowQuality; i++) // 沿光方向逐像素找遮挡。
                {
                    stepLength = min(totalStep.x, totalStep.y); // 先碰到的边界。
                    stepHeight = currHeight + stepLength * stepDir.z; // 这一步的高度。
                    stepNext = (floatBitsToInt(vec2(stepLength) - totalStep) >> 31) + 1; // 跨哪一侧。
                    shadowTexel += stepNext * sdirShadow; // 前进到下一个像素。
                    totalStep += vec2(stepNext) * ardirShadow; // 累加边界距离。
                    if (isBlock) shadowTexel = tilesPixelBase + (shadowTexel & resolutionMask); // 方块图集折回本图块。
                    sampleHeight = texelFetch(normals, shadowTexel, 0).a; // 读高度。
                    sampleHeight += ogxSaturate(1.0 - sampleHeight * 1e20); // 高度为零时补成完整高度。
                    if (sampleHeight > stepHeight) // 表面高过光线，说明被遮挡。
                    {
                        parallaxShadow = 0.0; // 直接判为阴影。
                        break; // 结束。
                    }
                }
                parallaxShadow *= fadeEnabled ? mix(1.0, shadow, fade) : shadow; // 远处淡出阴影，未开淡出时原样。
            }
        }
        hitNormal = ogxParallaxHitNormal(normals, parallaxTexel, hitNormal, fade, fadeEnabled, basedNormal); // 命中后按当前模式处理法线。
    }
    else if (basedNormal == 1) // 没命中侧面就退回贴图法线。
    {
        hitNormal = ogxDecodeNormalTex(texelFetch(normals, parallaxTexel, 0).rgb); // 没命中时直接用贴图法线。
    }
    if (basedNormal == 0) hitNormal = ogxDecodeNormalTex(texelFetch(normals, parallaxTexel, 0).rgb); // 不用视差法线时一律取贴图法线。
    return parallaxTexel; // 交回最终采样像素。
}

#endif
