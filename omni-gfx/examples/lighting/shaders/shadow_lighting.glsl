#ifndef LIGHTING_SHADOW_INCLUDED // 只定义一次，地表、水面与雾共用同一套阴影查询。
#define LIGHTING_SHADOW_INCLUDED
// 级联阴影采样：三级 PCSS 软阴影、交界混合与接触偏移。
// 调用位置：地表片元、水面片元与体积雾步进；在 `common.glsl` 之后引入。
// 设计原因与取舍：
//   阴影贴图名字写死而不把 sampler2D 当形参：这台英特尔驱动会把形参采样器解析到错误的纹理单元。
//   近景用遮挡物搜索加百分比过滤，半影随遮挡距离变宽；远景退化成小核 百分比过滤，省下填充成本。
//   法线偏移沿表面法线推开接收点，偏置按入射角放大，掠射面不出现条纹，也不会让影子离地。
//   镜头十六米内才做完整遮挡搜索；更远的地面一个阴影纹素已覆盖几十厘米。
//   再宽的半影只会变成噪点，所以中景与远景改用五点百分比过滤，既省填充也保持稳定。
//   三级的深度范围都在一千米上下，深度偏置按级联放大，斜坡上不会有条纹或悬空影子。
uniform sampler2D uShadowMap0; // 第一级阴影深度，覆盖近景。
uniform sampler2D uShadowMap1; // 第二级阴影深度，覆盖中景。
uniform sampler2D uShadowMap2; // 第三级阴影深度，覆盖远景。
uniform mat4 uShadowMatrix0; // 第一级光源视图投影。
uniform mat4 uShadowMatrix1; // 第二级光源视图投影。
uniform mat4 uShadowMatrix2; // 第三级光源视图投影。
uniform vec3 uCascadeSplits; // 三级分界距离，米。
uniform float uCascadeBlend; // 分界过渡宽度，米。
uniform float uShadowTexel; // 一个阴影纹素的大小，三级贴图同尺寸。

// 把世界点换到某一级阴影图的零到一坐标；法线偏移先加在世界坐标上。
vec3 lightingShadowCoord(mat4 matrix, vec3 worldPosition, vec3 normal, float normalBias) // 返回纹理坐标与深度。
{
    vec4 lightPosition = matrix * vec4(worldPosition + normal * normalBias, 1.0); // 光源裁剪空间位置。
    return lightPosition.xyz / max(lightPosition.w, 1e-5) * 0.5 + 0.5; // 负一到一换成零到一。
}

// 黄金角螺旋偏移：`index` 从零开始，`count` 是样本数，`rotation` 是整体旋转。
vec2 lightingSpiralOffset(int index, int count, vec2 rotation) // 返回单位圆内的偏移。
{
    float angle = float(index) * 2.399963229728653 + atan(rotation.y, rotation.x); // 黄金角加像素旋转。
    float radius = sqrt((float(index) + 0.5) / float(count)); // 圆面均匀分布。
    return vec2(cos(angle), sin(angle)) * radius; // 极坐标转直角。
}

// 近景五点 百分比过滤：用于大部分已经远离相机的地面，成本只有完整 PCSS 的三分之一。
float lightingPcf0(vec3 coordinate, float bias, vec2 rotation) // 返回零到一可见度。
{
    float texel = uShadowTexel * 1.4; // 略宽的核。
    vec2 offset = vec2(rotation.y, -rotation.x) * texel; // 旋转后的斜向偏移。
    float visible = 0.0; // 受光权重。
    visible += step(coordinate.z - bias, texture(uShadowMap0, coordinate.xy).r) * 0.36; // 中心。
    visible += step(coordinate.z - bias, texture(uShadowMap0, coordinate.xy + offset).r) * 0.16; // 右上。
    visible += step(coordinate.z - bias, texture(uShadowMap0, coordinate.xy - offset).r) * 0.16; // 左下。
    visible += step(coordinate.z - bias, texture(uShadowMap0, coordinate.xy + vec2(offset.x, -offset.y)).r) * 0.16; // 右下。
    visible += step(coordinate.z - bias, texture(uShadowMap0, coordinate.xy + vec2(-offset.x, offset.y)).r) * 0.16; // 左上。
    return visible; // 加权平均。
}

// PCSS 第一级：先找遮挡物平均深度，再按深度差决定过滤半径。
float lightingPcss0(vec3 coordinate, float bias, vec2 rotation) // 返回零到一可见度。
{
    float texel = uShadowTexel; // 纹素大小。
    float blockerSum = 0.0; // 遮挡物深度和。
    float blockerCount = 0.0; // 遮挡物样本数。
    for (int i = 0; i < 6; i++) // 六点搜索，覆盖球体边缘与硬边。
    {
        vec2 offset = lightingSpiralOffset(i, 6, rotation) * texel * 4.0; // 搜索半径四个纹素。
        float depth = texture(uShadowMap0, coordinate.xy + offset).r; // 该点最近遮挡物深度。
        if (depth < coordinate.z - bias) // 只有比接收点更近的样本才算遮挡。
        {
            blockerSum += depth; // 累加深度。
            blockerCount += 1.0; // 计数。
        }
    }
    if (blockerCount < 0.5) // 没有遮挡物：退回单点比较，保住曲面自阴影与薄物体阴影。
    {
        return step(coordinate.z - bias, texture(uShadowMap0, coordinate.xy).r); // 中心样本可见度。
    }
    float blocker = blockerSum / blockerCount; // 平均遮挡物深度。
    float gap = max(coordinate.z - blocker, 0.0); // 遮挡物与接收点的深度差。
    float radiusTexels = clamp(gap * 2600.0, 2.0, 13.0); // 半影至少两个纹素，边缘不会退化成硬边。
    float visible = 0.0; // 受光样本数。
    for (int i = 0; i < 6; i++) // 六点百分比过滤。
    {
        vec2 offset = lightingSpiralOffset(i, 6, rotation) * texel * radiusTexels; // 半影半径内的样本。
        float depth = texture(uShadowMap0, coordinate.xy + offset).r; // 读样本深度。
        visible += step(coordinate.z - bias, depth); // 接收点不深于样本就算受光。
    }
    return visible / 6.0; // 平均可见度。
}

// PCSS 第二级：样本减少到六加八，远处像素在画面上只占几像素。
float lightingPcss1(vec3 coordinate, float bias, vec2 rotation) // 返回零到一可见度。
{
    float texel = uShadowTexel; // 纹素大小。
    float blockerSum = 0.0; // 遮挡物深度和。
    float blockerCount = 0.0; // 遮挡物样本数。
    for (int i = 0; i < 6; i++) // 六点搜索。
    {
        vec2 offset = lightingSpiralOffset(i, 6, rotation) * texel * 5.0; // 搜索半径五个纹素。
        float depth = texture(uShadowMap1, coordinate.xy + offset).r; // 样本深度。
        if (depth < coordinate.z - bias) // 更近的样本才是遮挡物。
        {
            blockerSum += depth; // 累加。
            blockerCount += 1.0; // 计数。
        }
    }
    if (blockerCount < 0.5) // 没有遮挡：退回单点比较。
    {
        return step(coordinate.z - bias, texture(uShadowMap1, coordinate.xy).r); // 中心样本。
    }
    float gap = max(coordinate.z - blockerSum / blockerCount, 0.0); // 深度差。
    float radiusTexels = clamp(gap * 1800.0, 2.0, 9.0); // 第二级覆盖更大，半影上限略小。
    float visible = 0.0; // 受光样本数。
    for (int i = 0; i < 6; i++) // 六点过滤。
    {
        vec2 offset = lightingSpiralOffset(i, 6, rotation) * texel * radiusTexels; // 半影半径。
        float depth = texture(uShadowMap1, coordinate.xy + offset).r; // 样本深度。
        visible += step(coordinate.z - bias, depth); // 比较。
    }
    return visible / 6.0; // 平均。
}

// 中景五点 百分比过滤：远景不需要半影形状，五点核足够软，成本只有完整 PCSS 的三分之一。
float lightingPcf1(vec3 coordinate, float bias, vec2 rotation) // 返回零到一可见度。
{
    float texel = uShadowTexel * 1.6; // 略宽的核。
    vec2 offset = vec2(rotation.y, -rotation.x) * texel; // 用旋转向量产生一个斜向偏移。
    float visible = 0.0; // 受光权重。
    visible += step(coordinate.z - bias, texture(uShadowMap1, coordinate.xy).r) * 0.36; // 中心。
    visible += step(coordinate.z - bias, texture(uShadowMap1, coordinate.xy + offset).r) * 0.16; // 右上。
    visible += step(coordinate.z - bias, texture(uShadowMap1, coordinate.xy - offset).r) * 0.16; // 左下。
    visible += step(coordinate.z - bias, texture(uShadowMap1, coordinate.xy + vec2(offset.x, -offset.y)).r) * 0.16; // 右下。
    visible += step(coordinate.z - bias, texture(uShadowMap1, coordinate.xy + vec2(-offset.x, offset.y)).r) * 0.16; // 左上。
    return visible; // 加权平均。
}

// 第三级：五点十字 百分比过滤，远景阴影只需要整体明暗，不需要半影形状。
float lightingPcf2(vec3 coordinate, float bias) // 返回零到一可见度。
{
    float texel = uShadowTexel * 2.0; // 第三级核略宽。
    float visible = 0.0; // 受光样本数。
    visible += step(coordinate.z - bias, texture(uShadowMap2, coordinate.xy).r); // 中心。
    visible += step(coordinate.z - bias, texture(uShadowMap2, coordinate.xy + vec2(texel, 0.0)).r); // 右。
    visible += step(coordinate.z - bias, texture(uShadowMap2, coordinate.xy - vec2(texel, 0.0)).r); // 左。
    visible += step(coordinate.z - bias, texture(uShadowMap2, coordinate.xy + vec2(0.0, texel)).r); // 上。
    visible += step(coordinate.z - bias, texture(uShadowMap2, coordinate.xy - vec2(0.0, texel)).r); // 下。
    return visible / 5.0; // 平均。
}

// 主阴影查询：按视深度选级，交界处混合两级；`dither` 让每个像素的采样螺旋错开。
float lightingShadow(vec3 worldPosition, vec3 normal, float viewDepth, float dither) // 返回零到一太阳可见度。
{
    float facing = max(dot(normal, normalize(uSunDirection)), 0.0); // 表面朝太阳的程度。
    int cascade = viewDepth > uCascadeSplits.y ? 2 : (viewDepth > uCascadeSplits.x ? 1 : 0); // 选级。
    float farScale = cascade == 0 ? 1.0 : (cascade == 1 ? 2.6 : 7.0); // 级联越远，一个纹素覆盖的世界尺寸越大。
    float normalBias = (0.018 + 0.055 * (1.0 - facing)) * farScale; // 掠射与远景沿法线推开更多，避免条纹。
    float depthBias = 0.00004 + 0.00022 * (1.0 - facing) + (cascade == 2 ? 0.00055 : (cascade == 1 ? 0.00016 : 0.0)); // 远景加更大的深度偏置，压住斜坡条纹。
    vec2 rotation = vec2(cos(dither * 6.28318530718), sin(dither * 6.28318530718)); // 每个像素的螺旋旋转。
    float split = cascade == 0 ? uCascadeSplits.x : (cascade == 1 ? uCascadeSplits.y : uCascadeSplits.z); // 当前级分界。
    float blend = cascade < 2 ? clamp((viewDepth - (split - uCascadeBlend)) / max(uCascadeBlend, 1e-4), 0.0, 1.0) : 0.0; // 交界权重。
    vec3 coordinate; // 当前级阴影坐标。
    float primary; // 当前级可见度。
    if (cascade == 0) // 近景。
    {
        coordinate = lightingShadowCoord(uShadowMatrix0, worldPosition, normal, normalBias); // 第一级坐标。
        // 只有镜头附近真正需要软边与接触感的表面用完整 PCSS；大部分地面用五点 百分比过滤，省下填充成本。
        primary = viewDepth < 16.0 ? lightingPcss0(coordinate, depthBias, rotation) : lightingPcf0(coordinate, depthBias, rotation);
    }
    else if (cascade == 1) // 中景。
    {
        coordinate = lightingShadowCoord(uShadowMatrix1, worldPosition, normal, normalBias); // 第二级坐标。
        primary = lightingPcf1(coordinate, depthBias, rotation); // 中景五点 百分比过滤。
    }
    else // 远景。
    {
        coordinate = lightingShadowCoord(uShadowMatrix2, worldPosition, normal, normalBias); // 第三级坐标。
        primary = lightingPcf2(coordinate, depthBias); // 五点 百分比过滤。
    }
    // 阴影坐标出界说明两级覆盖范围不一致，出界时按受光处理，避免画面边缘出现黑框。
    if (any(lessThan(coordinate.xy, vec2(0.0))) || any(greaterThan(coordinate.xy, vec2(1.0)))) // 纹理范围判断。
    {
        return 1.0; // 不判阴影。
    }
    if (blend <= 0.001) // 不在交界带。
    {
        return primary; // 直接返回当前级。
    }
    vec3 nextCoord; // 下一级坐标。
    float secondary; // 下一级可见度。
    if (cascade == 0) // 零到一。
    {
        nextCoord = lightingShadowCoord(uShadowMatrix1, worldPosition, normal, normalBias); // 第二级。
        secondary = lightingPcf1(nextCoord, depthBias, rotation); // 第二级查询。
    }
    else // 一到二。
    {
        nextCoord = lightingShadowCoord(uShadowMatrix2, worldPosition, normal, normalBias); // 第三级。
        secondary = lightingPcf2(nextCoord, depthBias); // 第三级查询。
    }
    return mix(primary, secondary, blend); // 交界平滑过渡。
}

// 雾用的简化阴影：三点 百分比过滤，不做遮挡物搜索；雾每帧要采样十几次，成本必须低。
float lightingShadowCheap(vec3 worldPosition, vec3 normal, float viewDepth, float dither) // 返回零到一可见度。
{
    int cascade = viewDepth > uCascadeSplits.y ? 2 : (viewDepth > uCascadeSplits.x ? 1 : 0); // 选级。
    vec3 coordinate; // 阴影坐标。
    if (cascade == 0) // 近景。
    {
        coordinate = lightingShadowCoord(uShadowMatrix0, worldPosition, normal, 0.04); // 第一级。
    }
    else if (cascade == 1) // 中景。
    {
        coordinate = lightingShadowCoord(uShadowMatrix1, worldPosition, normal, 0.08); // 第二级。
    }
    else // 远景。
    {
        coordinate = lightingShadowCoord(uShadowMatrix2, worldPosition, normal, 0.16); // 第三级。
    }
    if (any(lessThan(coordinate.xy, vec2(0.0))) || any(greaterThan(coordinate.xy, vec2(1.0)))) // 出界。
    {
        return 1.0; // 受光。
    }
    float bias = 0.0006; // 雾点通常在半空，深度偏置取中间值。
    float texel = uShadowTexel * 1.5; // 略宽的核。
    vec2 offset = vec2(cos(dither * 6.28318530718), sin(dither * 6.28318530718)) * texel; // 每次步进取不同方向。
    float visible; // 可见度。
    if (cascade == 0) // 第一级贴图。
    {
        visible = step(coordinate.z - bias, texture(uShadowMap0, coordinate.xy).r) * 0.5; // 中心。
        visible += step(coordinate.z - bias, texture(uShadowMap0, coordinate.xy + offset).r) * 0.25; // 一个偏移。
        visible += step(coordinate.z - bias, texture(uShadowMap0, coordinate.xy - offset).r) * 0.25; // 另一个偏移。
    }
    else if (cascade == 1) // 第二级贴图。
    {
        visible = step(coordinate.z - bias, texture(uShadowMap1, coordinate.xy).r) * 0.5; // 中心。
        visible += step(coordinate.z - bias, texture(uShadowMap1, coordinate.xy + offset).r) * 0.25; // 偏移。
        visible += step(coordinate.z - bias, texture(uShadowMap1, coordinate.xy - offset).r) * 0.25; // 偏移。
    }
    else // 第三级贴图。
    {
        visible = step(coordinate.z - bias, texture(uShadowMap2, coordinate.xy).r) * 0.5; // 中心。
        visible += step(coordinate.z - bias, texture(uShadowMap2, coordinate.xy + offset).r) * 0.25; // 偏移。
        visible += step(coordinate.z - bias, texture(uShadowMap2, coordinate.xy - offset).r) * 0.25; // 偏移。
    }
    return visible; // 三点加权平均。
}

#endif // 阴影采样结束。
