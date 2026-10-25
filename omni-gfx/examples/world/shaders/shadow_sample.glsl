#ifndef SHADOW_SAMPLE_INCLUDED // 只引入一次，地形、道具与叶片共用同一套阴影采样。
#define SHADOW_SAMPLE_INCLUDED
// 测试世界共用的级联阴影采样：三级硬边核、交界混合与法线偏置。
// 调用位置：地形、树干与岩石、树叶与草的片元阶段，在 `world_shared.glsl` 之后引入。
// 设计原因与取舍：
//   阴影查询要传采样器，采样器形参在这台英特尔驱动上会被解析到错误的纹理单元，
//   所以每一级写一个直接引用阴影贴图名字的函数，再按级联编号分支调用。
//   每级用五点十字核而不是更大的循环，核越小越不容易出现指令缓存与寄存器压力；
//   远景不需要精确阴影，地形在九十米外直接跳过阴影查询。
//   法线偏置与深度偏置按入射角放大，掠射面不会出现条纹，同时保留树冠的接触暗部。
uniform sampler2D uShadowMap0; // 第一级阴影深度。
uniform sampler2D uShadowMap1; // 第二级阴影深度。
uniform sampler2D uShadowMap2; // 第三级阴影深度。
uniform mat4 uShadowMatrix0; // 第一级光源视图投影。
uniform mat4 uShadowMatrix1; // 第二级光源视图投影。
uniform mat4 uShadowMatrix2; // 第三级光源视图投影。
uniform vec3 uCascadeSplits; // 三级分界距离，米。
uniform float uCascadeBlend; // 分界过渡宽度，米。
// 调用方还要在包含本文件之前声明 uSunDirection 与 uFrame；它们同时服务雾、云与抖动，
// 放在这里重复声明会让某些驱动把 uniform 当成两个不同位置。

// 把世界点换到某一级阴影图的零到一坐标。
// 先加一点法线偏置，再乘光源矩阵；最后把透视除法后的坐标压进纹理范围。
vec3 shadowCoordinate(mat4 matrix, vec3 worldPosition, vec3 normal, float normalBias)
{
    vec4 lightPosition = matrix * vec4(worldPosition + normal * normalBias, 1.0); // 光源裁剪空间位置。
    return lightPosition.xyz / lightPosition.w * 0.5 + 0.5; // 负一到一换成零到一。
}

// 五点十字核：中心加四个方向各一个样本。
// 采样器直接写死名字，避免把采样器作为形参传给函数；返回值一是受光，零是阴影。
float pcfCascade0(vec3 coordinate, float bias, float radiusTexels)
{
    float texel = 1.0 / 512.0; // 阴影贴图边长与 Python 侧一致。
    if (coordinate.x < 0.0 || coordinate.x > 1.0 || coordinate.y < 0.0 || coordinate.y > 1.0
        || coordinate.z < 0.0 || coordinate.z > 1.0) return 1.0; // 范围外按受光处理。
    float stepSize = texel * radiusTexels; // 一个方向的偏移量。
    float visible = 0.0; // 受光样本数。
    visible += step(coordinate.z - bias, textureLod(uShadowMap0, coordinate.xy, 0.0).r); // 中心。
    visible += step(coordinate.z - bias, textureLod(uShadowMap0, coordinate.xy + vec2(stepSize, 0.0), 0.0).r); // 右。
    visible += step(coordinate.z - bias, textureLod(uShadowMap0, coordinate.xy - vec2(stepSize, 0.0), 0.0).r); // 左。
    visible += step(coordinate.z - bias, textureLod(uShadowMap0, coordinate.xy + vec2(0.0, stepSize), 0.0).r); // 上。
    visible += step(coordinate.z - bias, textureLod(uShadowMap0, coordinate.xy - vec2(0.0, stepSize), 0.0).r); // 下。
    return visible / 5.0; // 五个样本平均。
}

float pcfCascade1(vec3 coordinate, float bias, float radiusTexels)
{
    float texel = 1.0 / 512.0; // 第二级同样尺寸。
    if (coordinate.x < 0.0 || coordinate.x > 1.0 || coordinate.y < 0.0 || coordinate.y > 1.0
        || coordinate.z < 0.0 || coordinate.z > 1.0) return 1.0; // 超出该级就交给下一级。
    float stepSize = texel * radiusTexels; // 根据级联范围放大偏移，保持世界尺度半影。
    float visible = 0.0; // 受光样本数。
    visible += step(coordinate.z - bias, textureLod(uShadowMap1, coordinate.xy, 0.0).r); // 中心。
    visible += step(coordinate.z - bias, textureLod(uShadowMap1, coordinate.xy + vec2(stepSize, 0.0), 0.0).r); // 右。
    visible += step(coordinate.z - bias, textureLod(uShadowMap1, coordinate.xy - vec2(stepSize, 0.0), 0.0).r); // 左。
    visible += step(coordinate.z - bias, textureLod(uShadowMap1, coordinate.xy + vec2(0.0, stepSize), 0.0).r); // 上。
    visible += step(coordinate.z - bias, textureLod(uShadowMap1, coordinate.xy - vec2(0.0, stepSize), 0.0).r); // 下。
    return visible / 5.0; // 平均后作为可见度。
}

float pcfCascade2(vec3 coordinate, float bias, float radiusTexels)
{
    float texel = 1.0 / 512.0; // 第三级覆盖最远，核也最宽。
    if (coordinate.x < 0.0 || coordinate.x > 1.0 || coordinate.y < 0.0 || coordinate.y > 1.0
        || coordinate.z < 0.0 || coordinate.z > 1.0) return 1.0; // 范围外不判阴影。
    float stepSize = texel * radiusTexels; // 世界尺度半影换算到纹理坐标。
    float visible = 0.0; // 受光样本数。
    visible += step(coordinate.z - bias, textureLod(uShadowMap2, coordinate.xy, 0.0).r); // 中心。
    visible += step(coordinate.z - bias, textureLod(uShadowMap2, coordinate.xy + vec2(stepSize, 0.0), 0.0).r); // 右。
    visible += step(coordinate.z - bias, textureLod(uShadowMap2, coordinate.xy - vec2(stepSize, 0.0), 0.0).r); // 左。
    visible += step(coordinate.z - bias, textureLod(uShadowMap2, coordinate.xy + vec2(0.0, stepSize), 0.0).r); // 上。
    visible += step(coordinate.z - bias, textureLod(uShadowMap2, coordinate.xy - vec2(0.0, stepSize), 0.0).r); // 下。
    return visible / 5.0; // 平均后作为可见度。
}

// 级联阴影：按视深度选级，交界处两级混合。
// 参数一是世界坐标，二是几何法线，三是到相机的距离，四是沿法线的偏移，五是核半径。
// 先算偏置：正对光源时半米左右，掠射时逐渐增大，避免表面自阴影。
// 再按 `cascade` 分支取样；只有交界带才付出第二级的采样成本。
float shadowVisibility(vec3 worldPosition, vec3 normal, float viewDepth, float normalBias, float searchRadius)
{
    OgxCascadeSelect cascade = ogxSelectCascade(viewDepth, uCascadeSplits, uCascadeBlend); // 选级与过渡权重。
    float facing = max(dot(normal, normalize(uSunDirection)), 0.0); // 表面朝向太阳的程度。
    float bias = 0.00005 + 0.00045 * (1.0 - facing); // 掠射面需要更大的深度偏置。
    vec3 coordinate = shadowCoordinate(uShadowMatrix0, worldPosition, normal, normalBias); // 先按第一级算坐标。
    float primary; // 主要一级的可见度。
    if (cascade.index == 0)
    {
        primary = pcfCascade0(coordinate, bias, searchRadius * 0.8); // 近景核窄一些，影子边缘更利。
    }
    else if (cascade.index == 1)
    {
        coordinate = shadowCoordinate(uShadowMatrix1, worldPosition, normal, normalBias); // 换到第二级矩阵。
        primary = pcfCascade1(coordinate, bias, searchRadius * 1.4); // 中景核略宽。
    }
    else
    {
        coordinate = shadowCoordinate(uShadowMatrix2, worldPosition, normal, normalBias); // 换到第三级矩阵。
        primary = pcfCascade2(coordinate, bias, searchRadius * 2.2); // 远景核最宽。
    }
    if (cascade.weight <= 0.001) // 不在交界带就直接返回，省掉第二组采样。
    {
        return primary; // 只有一级的结果。
    }
    vec3 secondaryCoordinate = shadowCoordinate(cascade.next == 1 ? uShadowMatrix1 : uShadowMatrix2,
                                                worldPosition, normal, normalBias); // 下一级坐标。
    float secondary; // 过渡级可见度。
    if (cascade.next == 1)
    {
        secondary = pcfCascade1(secondaryCoordinate, bias, searchRadius * 1.4); // 第二级。
    }
    else
    {
        secondary = pcfCascade2(secondaryCoordinate, bias, searchRadius * 2.2); // 第三级。
    }
    return mix(primary, secondary, cascade.weight); // 按过渡权重混合。
}
#endif // 阴影采样结束。
