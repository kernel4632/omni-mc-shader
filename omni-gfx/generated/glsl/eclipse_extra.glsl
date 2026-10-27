/*
生成文件：Eclipse 补充模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库 Eclipse 补充模块：环境光遮蔽、阴影压缩、雾相位、颜色抖动与闪电。
调用位置：需要复现 Eclipse 小工具的后期与光照程序；Minecraft 光影由 `/omni-gfx/eclipse_extra.glsl` 引入。
可复制示例：
    float ao = ogxEclipseAmbientOcclusion(screenPos, viewPos, normal, dither, depthTex, viewport, viewPixel, handDepth);
    vec3 d = ogxEclipseFp10Dither(color, texCoord, frameTime);
设计原因与取舍：
    这些函数在原程序里直接依赖全局深度图、矩阵与天气。库把纹理、尺寸、阈值与噪声全部改为参数，
    函数体保留原来的常数与采样顺序。调试文字、实体枚举与菜单不在这里，仍留在宿主。
*/
#ifndef OGX_ECLIPSE_EXTRA_INCLUDED
#define OGX_ECLIPSE_EXTRA_INCLUDED

// 相机变换与数学提供投影、夹紧和反余弦。
#include "/omni-gfx/camera.glsl"
#include "/omni-gfx/math.glsl"
// GTAO 的弧段积分：两个水平角之间覆盖的余弦积分。
float ogxEclipseIntegrateArc(vec2 h, float n, float cosN)
{
    vec2 tmp = cosN + 2.0 * h * sin(n) - cos(2.0 * h - n); // 参考实现的积分核。
    return 0.25 * (tmp.x + tmp.y); // 两个方向取平均。
}

// 单个切片的最大水平角：沿切片方向在深度图里找最高遮挡。
float ogxEclipseMaxHorizonAngle(vec3 viewSliceDir, vec3 viewerDir, vec3 screenPos, vec3 viewPos, float dither,
    float radius, int steps, vec3 viewPixelSize, vec2 viewRes, float renderScale, float handDepth,
    float falloffStart, sampler2D depthTexture, mat4 projection, mat4 projectionInverse)
{
    float stepSize = radius / float(steps); // 每步的视空间长度。
    float maxCosTheta = -1.0; // 最大遮挡角余弦。
    vec3 endScreen = ogxViewToScreenSpace(viewPos + viewSliceDir * stepSize, projection); // 一步后的屏幕坐标。
    vec2 rayStep = endScreen.xy - screenPos.xy; // 屏幕步长。
    float pixelScale = max(viewPixelSize.x, max(viewPixelSize.y, viewPixelSize.z)); // 最大像素尺度。
    vec2 rayPos = screenPos.xy + rayStep * (dither + pixelScale / length(rayStep)); // 起点加抖动与一个像素偏移。
    for (int i = 0; i < steps; ++i) // 逐步采样。
    {
        ivec2 pixel = ivec2(clamp(rayPos, 0.0, 1.0) * viewRes * renderScale - 0.5); // 屏幕比例换像素。
        float depth = texelFetch(depthTexture, pixel, 0).x; // 读深度。
        if (depth == 1.0 || depth < handDepth || depth == screenPos.z) // 天空、手与自身都跳过。
        {
            rayPos += rayStep;
            continue;
        }
        vec3 offset = ogxScreenToViewSpace(vec3(rayPos, depth), projectionInverse) - viewPos; // 采样点相对当前点的视空间偏移。
        float lenSq = dot(offset, offset); // 距离平方。
        float norm = inversesqrt(lenSq); // 距离倒数。
        float distanceFalloff = ogxSaturate((lenSq * norm - falloffStart * radius) / (radius - falloffStart * radius)); // 距离淡出。
        float cosTheta = dot(viewerDir, offset) * norm; // 夹角余弦。
        cosTheta = mix(cosTheta, -1.0, distanceFalloff); // 远处压到水平线以下。
        maxCosTheta = max(cosTheta, maxCosTheta); // 取最大。
        rayPos += rayStep;
    }
    return ogxFastAcosEclipse(clamp(maxCosTheta, -1.0, 1.0)); // 反余弦得到角度。
}

// GTAO 环境光遮蔽：沿多个切片各取两个最大水平角，再积分成遮蔽。
float ogxEclipseAmbientOcclusion(vec3 screenPos, vec3 viewPos, vec3 viewNormal, vec2 dither, int slices,
    float radius, int horizonSteps, float falloffStart, vec3 viewPixelSize, vec2 viewRes, float renderScale,
    float handDepth, float halfPi, sampler2D depthTexture, mat4 projection, mat4 projectionInverse)
{
    float ao = 0.0; // 累加遮蔽。
    vec3 viewerDir = normalize(-viewPos); // 视线方向。
    vec3 viewerRight = normalize(cross(vec3(0.0, 1.0, 0.0), viewerDir)); // 右方向。
    vec3 viewerUp = cross(viewerDir, viewerRight); // 上方向。
    mat3 localToView = mat3(viewerRight, viewerUp, viewerDir); // 局部到视空间。
    for (int i = 0; i < slices; ++i) // 逐切片。
    {
        float sliceAngle = (float(i) + dither.x) * (OGX_PI / float(slices)); // 切片角。
        vec3 sliceDir = vec3(cos(sliceAngle), sin(sliceAngle), 0.0); // 切片方向。
        vec3 viewSliceDir = ogxMatrix3MulPoint(localToView, sliceDir); // 转到视空间。
        vec3 orthoDir = sliceDir - dot(sliceDir, viewerDir) * viewerDir; // 切片在视线垂直平面的投影。
        vec3 axis = cross(sliceDir, viewerDir); // 旋转轴。
        vec3 projectedNormal = viewNormal - axis * dot(viewNormal, axis); // 法线投影。
        float lenSq = dot(projectedNormal, projectedNormal); // 投影长度平方。
        float norm = inversesqrt(lenSq); // 倒数。
        float signGamma = sign(dot(orthoDir, projectedNormal)); // 法线在切片哪一侧。
        float cosGamma = ogxSaturate(dot(projectedNormal, viewerDir) * norm); // 法线与视线夹角余弦。
        float gamma = signGamma * ogxFastAcosEclipse(cosGamma); // 夹角。
        vec2 maxHorizonAngles; // 两个方向的最大水平角。
        maxHorizonAngles.x = ogxEclipseMaxHorizonAngle(-viewSliceDir, viewerDir, screenPos, viewPos, dither.y, radius,
            horizonSteps, viewPixelSize, viewRes, renderScale, handDepth, falloffStart, depthTexture, projection, projectionInverse); // 负方向。
        maxHorizonAngles.y = ogxEclipseMaxHorizonAngle(viewSliceDir, viewerDir, screenPos, viewPos, dither.y, radius,
            horizonSteps, viewPixelSize, viewRes, renderScale, handDepth, falloffStart, depthTexture, projection, projectionInverse); // 正方向。
        maxHorizonAngles = gamma + clamp(vec2(-1.0, 1.0) * maxHorizonAngles - gamma, -halfPi, halfPi); // 限制在半球内。
        ao += ogxEclipseIntegrateArc(maxHorizonAngles, gamma, cosGamma) * lenSq * norm; // 积分这一段。
    }
    ao *= 1.0 / float(slices); // 取平均。
    return ao * (ao * 0.5 + 0.5); // 参考实现的对比度重整。
}

// Eclipse 阴影边缘压缩：按到阴影图中心的距离给一个放大系数。
float ogxEclipseCalcDistort(vec2 worldPos, float a, float b, float k)
{
    return 1.0 / (log(length(worldPos) * b + a) * k); // 参考实现对数的边缘压缩。
}

// Eclipse 阴影投影偏差：读入齐次阴影坐标，按同一压缩系数缩放横纵。
vec4 ogxEclipseBiasShadowProjection(vec4 projectedShadowSpacePosition, float a, float b, float k)
{
    float distortFactor = log(length(projectedShadowSpacePosition.xy) * b + a) * k; // 与读取端一致。
    projectedShadowSpacePosition.xy /= distortFactor; // 压缩横纵。
    return projectedShadowSpacePosition; // 交回坐标。
}

// 硬阴影：阴影图深度比接收点更远时返回零，否则一。
float ogxEclipseCalculateHardShadows(float shadowDepth, vec3 shadowPosition, float bias)
{
    if (shadowPosition.z >= 1.0) return 1.0; // 阴影图外保持全亮。
    return 1.0 - step(shadowDepth, shadowPosition.z - bias); // 参考实现的阶跃比较。
}

// 自定义旋转矩阵：绕倾斜轴旋转一天的时间角，供月亮轨道与阴影相机使用。
mat3 ogxEclipseCustomRotation(float rotationAngle, float timeOfDay)
{
    float radiance = timeOfDay / 24000.0 * 6.28319; // 一天转一圈。
    float sunRotRad = radians(rotationAngle); // 倾斜角。
    vec3 rotationAxis = vec3(0.0, sin(sunRotRad), cos(sunRotRad)); // 倾斜轴。
    float c = cos(radiance); // 旋转余弦。
    float s = sin(radiance); // 旋转正弦。
    float t = 1.0 - c; // 一减余弦。
    mat3 tiltRotation = mat3(
        t * rotationAxis.x * rotationAxis.x + c,
        t * rotationAxis.x * rotationAxis.y - s * rotationAxis.z,
        t * rotationAxis.x * rotationAxis.z + s * rotationAxis.y,
        t * rotationAxis.y * rotationAxis.x + s * rotationAxis.z,
        t * rotationAxis.y * rotationAxis.y + c,
        t * rotationAxis.y * rotationAxis.z - s * rotationAxis.x,
        t * rotationAxis.z * rotationAxis.x - s * rotationAxis.y,
        t * rotationAxis.z * rotationAxis.y + s * rotationAxis.x,
        t * rotationAxis.z * rotationAxis.z + c); // 按列填写的旋转矩阵。
    return tiltRotation; // 交回旋转。
}

// 法线夹紧：把背向视线的法线朝视线方向拉回，避免掠射高光发黑。
vec3 ogxEclipseClampNormal(vec3 n, vec3 v)
{
    float nDotV = ogxSaturate(dot(n, -v)); // 法线与视线夹角余弦。
    return normalize(nDotV * v + n); // 参考实现的混合。
}

// 笛卡尔坐标转球面纹理坐标。
vec3 ogxEclipseCartToSphere(vec2 coord)
{
    coord.y = 1.0 - coord.y; // 翻转纵轴。
    coord *= vec2(2.0 * OGX_PI, OGX_PI); // 换成角度。
    vec2 lon = vec2(sin(coord.x), cos(coord.x)) * sin(coord.y); // 经度方向。
    return vec3(lon.x, cos(coord.y), lon.y); // 单位球方向。
}

// 球面方向转笛卡尔纹理坐标。
vec2 ogxEclipseSphereToCart(vec3 dir)
{
    float lonlat = atan(-dir.x, -dir.z); // 经度。
    return vec2(lonlat / (2.0 * OGX_PI) + 0.5, 0.5 * dir.y + 0.5); // 与上一函数互逆。
}

// 雾相位：Eclipse 的指数相位，光线越正对越亮。
float ogxEclipseFogPhase(float lightPoint)
{
    float linear = clamp(-lightPoint * 0.5 + 0.5, 0.001, 1.0); // 线性项。
    float linear2 = 1.0 - clamp(lightPoint, 0.0, 1.0); // 参考保留这一项，当前返回值没有用到它。
    float exponential = exp2(pow(linear, 0.3) * -15.0) * 1.5; // 指数项。
    exponential += sqrt(exp2(sqrt(linear) * -12.5)); // 开方项。
    return exponential; // 交回相位。
}

// 三角白噪声：中心化后开方，得到更适合抖动的分布。
float ogxEclipseTriangWhiteNoise(vec2 n, float frameTime)
{
    float t = fract(frameTime); // 帧内小数。
    float rnd = fract(sin(dot(n + 0.07 * t, vec2(12.9898, 78.233))) * 43758.5453); // 白噪声。
    float center = rnd * 2.0 - 1.0; // 中心化。
    rnd = center * inversesqrt(abs(center) + 1e-20); // 开方。
    rnd = max(-1.0, rnd); // 下限。
    return rnd - sign(center); // 三角分布。
}

// 按浮点尾数位抖动颜色：十位、十六位与整数八九十十六位各一版。
vec3 ogxEclipseDither(vec3 color, vec2 texCoord, float frameTime, int mode)
{
    float dither = ogxEclipseTriangWhiteNoise(texCoord, frameTime); // 抖动值。
    if (mode == 0) return color + dither * exp2(-vec3(6.0, 6.0, 5.0)) * exp2(floor(log2(color))); // 十位尾数。
    if (mode == 1) return color + dither * exp2(-10.0) * exp2(floor(log2(color))); // 十六位尾数。
    if (mode == 2) return color + dither * exp2(-8.0); // 八位整数。
    if (mode == 3) return color + dither * exp2(-10.0); // 十位整数。
    return color + dither * exp2(-16.0); // 十六位整数。
}

// 闪电照亮表面：距离衰减、次表面相位与法线朝向一起决定亮度。
vec3 ogxEclipseLightningFlash(vec3 feetPlayerPos, vec4 boltPosition, vec3 worldNormal, vec3 lightningEffect,
    inout float phase)
{
    if (boltPosition.w <= 0.0) return vec3(0.0); // 没有闪电。
    vec3 lightningPos = feetPlayerPos - vec3(boltPosition.x, clamp(feetPlayerPos.y, boltPosition.y + 16.0, boltPosition.y + 116.0), boltPosition.z); // 闪电到表面。
    float lightDistance = 300.0; // 照明半径。
    float lightningLight = max(1.0 - length(lightningPos) / lightDistance, 0.0); // 线性衰减。
    lightningLight = exp((1.0 - lightningLight) * -10.0); // 指数重整。
    vec3 phasePos = normalize(feetPlayerPos) + vec3(boltPosition.x, boltPosition.y + 60.0, boltPosition.z); // 相位方向。
    float phaseOrigin = 1.0 - ogxSaturate(dot(normalize(feetPlayerPos), normalize(phasePos))); // 相位夹角。
    phase = exp(sqrt(phaseOrigin) * -2.0) * 5.0 * lightningLight; // 次表面相位。
    float ndotl = ogxSaturate(dot(lightningPos, -worldNormal)); // 法线朝向。
    return lightningEffect * lightningLight * ndotl; // 最终闪电。
}

// Eclipse 闪电照亮表面入口：参考签名的第二个位置参数不使用，真实位置来自 vec4 闪电缓冲。
// 为什么保留这个空参数：外部调用点按参考签名传参，库只把真实位置显式接进来。
vec3 ogxItxIrisLightningflash(vec3 feetPlayerPos, vec3 lightningBoltPos, vec3 worldNormal,
    inout float phase, vec4 boltPosition, vec3 lightningEffect)
{
    return ogxEclipseLightningFlash(feetPlayerPos, boltPosition, worldNormal, lightningEffect, phase);
}

// 闪电照亮体积云：只按距离衰减。
vec3 ogxEclipseLightningCloud(vec3 feetPlayerPos, vec4 boltPosition, vec3 lightningEffect)
{
    if (boltPosition.w <= 0.0) return vec3(0.0); // 没有闪电。
    vec3 lightningPos = feetPlayerPos - vec3(boltPosition.x, clamp(feetPlayerPos.y, boltPosition.y, boltPosition.y + 116.0), boltPosition.z); // 相对位置。
    float lightningLight = max(1.0 - length(lightningPos) / 400.0, 0.0); // 线性衰减。
    lightningLight = exp((1.0 - lightningLight) * -10.0); // 指数重整。
    return lightningEffect * lightningLight; // 交回闪电色。
}

// 闪电照亮体积雾：只在闪电强度大于一时生效。
vec3 ogxEclipseLightningFog(vec3 feetPlayerPos, vec4 boltPosition, vec3 lightningEffect)
{
    if (boltPosition.w <= 0.0 || boltPosition.w < 1.0) return vec3(0.0); // 弱闪电不照雾。
    vec3 lightningPos = feetPlayerPos - vec3(boltPosition.x, clamp(feetPlayerPos.y, boltPosition.y, boltPosition.y + 116.0), boltPosition.z); // 相对位置。
    float lightningLight = max(1.0 - length(lightningPos) / 150.0, 0.0); // 线性衰减。
    lightningLight = exp((1.0 - lightningLight) * -15.0); // 指数重整。
    return lightningEffect * lightningLight; // 交回闪电色。
}

// 末地光源位置：闪电位置吸到两百格网格，再按体积权重混向中心光柱。
vec3 ogxEclipseLightSourcePosition(vec3 worldPos, vec3 cameraPos, float vortexBounds, vec3 manualLightPos,
    vec3 randomOffset, bool theOrb)
{
    vec3 vortexPos = worldPos - vec3(0.0, 200.0, 0.0); // 中心光柱。
    vec3 lightningPos = worldPos - cameraPos - manualLightPos; // 闪电光。
    float cellSize = 200.0; // 网格大小。
    lightningPos += fract(cameraPos / cellSize) * cellSize - cellSize * 0.5; // 吸到网格。
    lightningPos -= randomOffset * 2.5; // 随机偏移。
    if (theOrb) return lightningPos; // 宝珠模式只看闪电位置。
    return mix(lightningPos, vortexPos, vortexBounds); // 按体积混合。
}

// iterationT 末地光源位置入口：先从第四张缓冲的固定像素取随机偏移，再调用主公式。
// 为什么单独一层：参考函数内部直接读 `colortex4`，主公式把随机偏移当参数；
// 严格对照需要把这次取像素放回函数体。
vec3 ogxItxLightSourcePosition(vec3 worldPos, vec3 cameraPos, float vortexBounds,
    sampler2D randomTexture, ivec2 randomTexel, vec3 manualLightPos, bool theOrb)
{
    vec3 randomOffset = (texelFetch(randomTexture, randomTexel, 0).xyz / 150.0) * 2.0 - 1.0; // 参考实现的随机偏移。
    return ogxEclipseLightSourcePosition(worldPos, cameraPos, vortexBounds, manualLightPos,
        randomOffset, theOrb); // 主公式原样转发。
}

// 末地光源颜色：闪电色与光柱色按体积权重混合。
vec3 ogxEclipseLightSourceColors(float vortexBounds, float lightningflash, vec3 vortexColor, vec3 lightningColor,
    vec3 orbColor, float orbMult, bool theOrb)
{
    vec3 lightning = lightningColor * lightningflash; // 闪电色按强度缩放。
    if (theOrb) return orbColor * orbMult; // 宝珠模式。
    return mix(lightning, vortexColor, vortexBounds); // 按体积混合。
}

// Frisvad 切线基：由法线直接构造两个正交切向，避免叉乘退化。
mat3 ogxEclipseFrisvad(vec3 n)
{
    vec3 f; // 第一切向。
    vec3 r; // 第二切向。
    if (n.z < -0.9) // 法线接近负 z 时用固定基，避免除以接近零的数。
    {
        f = vec3(0.0, -1.0, 0.0);
        r = vec3(-1.0, 0.0, 0.0);
    }
    else
    {
        float a = 1.0 / (1.0 + n.z); // 参考实现的比例。
        float b = -n.x * n.y * a; // 交叉项。
        f = vec3(1.0 - n.x * n.x * a, b, -n.x);
        r = vec3(b, 1.0 - n.y * n.y * a, -n.y);
    }
    return mat3(f, r, n); // 三列依次是切向、副切向、法线。
}

// 可见法线 GGX 采样：把视线压到半球椭球，再采一个半程方向。
vec3 ogxEclipseSampleVndfGgx(vec3 viewerDirection, float alpha, vec2 xy)
{
    viewerDirection = normalize(vec3(alpha * 0.5 * viewerDirection.xy, viewerDirection.z)); // 压到半球配置。
    const float tau = 6.2831853; // 参考实现的两倍圆周。
    float phi = tau * xy.x; // 采样角。
    float cosTheta = (1.0 - xy.y) * (1.0 + viewerDirection.z) - viewerDirection.z; // 余弦。
    float sinTheta = sqrt(clamp(1.0 - cosTheta * cosTheta, 0.0, 1.0)); // 正弦。
    sinTheta = clamp(sinTheta, 0.0, 1.0); // 参考实现的钳制。
    cosTheta = clamp(cosTheta, sinTheta * 0.5, 1.0); // 参考实现的钳制。
    vec3 reflected = vec3(vec2(cos(phi), sin(phi)) * sinTheta, cosTheta); // 反射方向。
    vec3 halfway = reflected + viewerDirection; // 半程方向。
    return normalize(vec3(alpha * halfway.xy, halfway.z)); // 回到椭球配置。
}

// Eclipse 的 GGX：粗糙度先取 2.5 次方，再算 D、F 与可见性。
vec3 ogxEclipseGgx(vec3 n, vec3 v, vec3 l, float r, vec3 f0, vec3 metalAlbedoTint)
{
    r = max(pow(r, 2.5), 0.0001); // 粗糙度重整与下限。
    vec3 h = normalize(l + v); // 半程方向。
    float hn = inversesqrt(dot(h, h)); // 半程长度倒数。
    float dotLH = clamp(dot(h, l) * hn, 0.0, 1.0); // 半程与光。
    float dotNH = clamp(dot(h, n) * hn, 0.0, 1.0); // 半程与法线。
    float dotNL = clamp(dot(n, l), 0.0, 1.0); // 法线与光。
    float dotNHsq = dotNH * dotNH; // 平方。
    float denom = dotNHsq * r - dotNHsq + 1.0; // 分母。
    float d = r / (3.141592653589793 * denom * denom); // 法线分布。
    vec3 f = (f0 + (1.0 - f0) * exp2((-5.55473 * dotLH - 6.98316) * dotLH)) * metalAlbedoTint; // 菲涅耳。
    float k2 = 0.25 * r; // 可见性系数。
    return dotNL * d * f / (dotLH * dotLH * (1.0 - k2) + k2); // 合成高光。
}

// Eclipse 的粗糙度菲涅耳：按粗糙度调整曲线与亮度。
float ogxEclipseShlickFresnelRoughness(float xDotN, float roughness)
{
    float shlickFresnel = clamp(1.0 + xDotN, 0.0, 1.0); // 基础菲涅耳。
    float curves = exp(-4.0 * pow(1.0 - roughness, 2.5)); // 曲线权重。
    float brightness = exp(-3.0 * pow(1.0 - sqrt(roughness), 3.50)); // 亮度权重。
    shlickFresnel = pow(1.0 - pow(1.0 - shlickFresnel, mix(1.0, 1.9, curves)), mix(5.0, 2.6, curves)); // 曲线重整。
    shlickFresnel = mix(0.0, mix(1.0, 0.065, brightness), clamp(shlickFresnel, 0.0, 1.0)); // 亮度重整。
    return shlickFresnel; // 交回菲涅耳。
}

// 体素平面求交：只接受落在两格以内且仍在同一格内的交点。
bool ogxEclipsePlaneIntersect(inout vec3 currPos, float worldOffset, inout vec3 voxelPos, vec3 reflectedVector,
    inout vec3 stepAxis, vec3 normal)
{
    float denom = dot(reflectedVector, normal); // 平面法线与射线。
    if (abs(denom) < 1e-6) return false; // 平行。
    float t = -(dot(currPos, normal) - worldOffset) / denom; // 交点参数。
    if (t > 0.0 && t < 2.0) // 只接受近处交点。
    {
        vec3 hitPos = currPos + t * reflectedVector; // 交点。
        if (all(equal(ivec3(voxelPos), ivec3(hitPos)))) // 仍在同一格。
        {
            currPos = hitPos;
            stepAxis = normal;
            return true;
        }
    }
    return false; // 没有有效交点。
}

// 体素包围盒求交：返回是否命中，并把位置推进到入口。
bool ogxEclipseAabbIntersection(inout vec3 currPos, vec3 reflectedVector, vec3 stepSizes, vec3 boxMin,
    vec3 boxMax, inout vec3 stepAxis)
{
    vec3 t1 = (boxMin - currPos) * stepSizes; // 近平面参数。
    vec3 t2 = (boxMax - currPos) * stepSizes; // 远平面参数。
    vec3 tmin = min(t1, t2); // 每轴入口。
    vec3 tmax = max(t1, t2); // 每轴出口。
    float tmin0 = max(max(tmin.x, tmin.y), tmin.z); // 最晚入口。
    float tmax0 = min(min(tmax.x, tmax.y), tmax.z); // 最早出口。
    bool hit = tmin0 < tmax0 && tmin0 > 0.0; // 有效区间。
    float fHit = float(hit); // 转浮点。
    vec3 entryDist = abs(tmin - vec3(tmin0)); // 哪一轴最先进入。
    vec3 normal = step(entryDist, vec3(0.0)); // 入口轴标记。
    stepAxis = mix(stepAxis, normal, fHit); // 命中时更新轴。
    currPos = mix(currPos, currPos + tmin0 * reflectedVector, fHit); // 命中时推进到入口。
    return hit; // 交回命中。
}

// 体素采样螺旋：把样本序号变成单位圆上的螺旋点，2.26 是参考实现的关键常数。
vec2 ogxEclipseCleanVoxelSample(int samples, float totalSamples, float noise)
{
    float variance = noise * 0.897; // 每像素抖动。
    float variedSamples = float(samples) + variance; // 抖动后的样本号。
    float spiralShape = sqrt(variedSamples / (totalSamples + variance)); // 半径。
    float shape = 2.26; // 参考实现的关键旋转系数。
    float theta = variedSamples * (OGX_PI * shape); // 角度。
    return vec2(cos(theta) * spiralShape, sin(theta) * spiralShape); // 螺旋点。
}

#endif
