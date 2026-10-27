/*
生成文件：Eclipse 天空模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库 Eclipse 天空模块：太阳与月亮圆盘、球面投影、三次纹理采样、天空盒查表、大气积分与极光。
调用位置：需要复现 Eclipse `sky_gradient.glsl`、`ROBOBO_sky.glsl` 与 `aurora.glsl` 的天空程序；
    Minecraft 光影由 `/omni-gfx/eclipse_sky.glsl` 引入，当前只由严格 profile 与独立测试消费。
可复制示例：
    vec3 sun = ogxEclipseDrawSun(dot(viewDir, sunDir), sunlightColor);
    vec2 uv = ogxEclipseSphereMap(screenUv);
    vec3 sky = ogxEclipseCalculateAtmosphere(background, viewDir, up, sunDir, moonDir,
        eyeAltitude, cameraY, sunColor, moonColor, 32, noise, 6000.0, true, true, false,
        rayleigh, mie, ozone, pid, transmittance);
设计原因与取舍：
    参考实现直接读 `texelSize`、`cameraPosition`、`worldShadowVector` 与一堆菜单宏。库把纹理尺寸、
    相机高度、光方向、系数与开关全部改成显式参数；公式、常数、循环次数与采样顺序保持不变。
    这样同一套天空可以用于独立测试世界、严格 profile 与 Minecraft，而库本身不读取宿主状态。
    纹理函数只接收采样器与尺寸，不绑定缓冲编号；调用方决定把哪张图放在哪个槽位。
*/
#ifndef OGX_ECLIPSE_SKY_INCLUDED
#define OGX_ECLIPSE_SKY_INCLUDED

// 数学提供圆周率、夹紧与黑体色；大气提供射线求交与相函数。
#include "/omni-gfx/math.glsl"
#include "/omni-gfx/atmosphere.glsl"
// Eclipse 太阳圆盘：按视方向与太阳方向的余弦算柔边，再乘太阳颜色与固定亮度。
vec3 ogxEclipseDrawSun(float cosY, vec3 sunlight)
{
    return sunlight / 0.0008821203 * pow(smoothstep(cos(0.0093084168595 * 3.2), cos(0.0093084168595 * 2.2), cosY), 3.0) * 0.62; // 常数与参考实现逐项相同。
}

// Eclipse 球面屏幕映射：把正方形屏幕的每一个点投到球面经纬度。
// 圆外返回零：调用方读到的贴图坐标落在左上角，不会越界采样。
vec2 ogxEclipseSphereMap(vec2 uv)
{
    vec2 position = 2.0 * uv - 1.0; // 屏幕坐标转负一到一。
    float radius = dot(position, position); // 到中心的距离平方。
    if (radius > 1.0) return vec2(0.0); // 圆外没有球面方向。
    float z = sqrt(1.0 - radius); // 球面上的第三分量。
    float longitude = atan(position.x, z); // 经度。
    float latitude = acos(position.y); // 纬度。
    float u = (longitude + OGX_PI) / (2.0 * OGX_PI); // 经度映射到零到一。
    float v = latitude / OGX_PI; // 纬度映射到零到一。
    return vec2(u, v); // 交回贴图坐标。
}

// Eclipse 默认月亮：一个很小的软圆盘，并压暗它后面的星星。
// `occludeStars` 是输入输出参数：月亮越亮，返回时星星遮罩越小。
vec3 ogxEclipseDrawMoon(vec3 playerPos, vec3 worldSunVec, vec3 color, inout float occludeStars)
{
    float shape = min(max(dot(worldSunVec, playerPos) - 0.9994, 0.0) / (1.0 - 0.9994), 1.0); // 月亮圆盘的软边。
    occludeStars *= max(1.0 - shape * 5.0, 0.0); // 圆盘附近遮住星星。
    return shape * color * 40.0; // 参考实现的月亮亮度。
}

// Eclipse 真实月亮：尺寸可调，边缘比默认月亮更软，星星遮挡更强。
vec3 ogxEclipseDrawRealMoon(vec3 playerPos, vec3 worldSunVec, vec3 color, inout float occludeStars, float size)
{
    float shape = min(max(dot(worldSunVec, playerPos) - size, 0.0) / (1.0 - size), 1.0); // 圆盘软边。
    shape = pow(shape, 0.15); // 参考实现的幂次让边缘更宽。
    occludeStars *= max(1.0 - shape * 50.0, 0.0); // 真实月亮遮住更多星星。
    return color / 750.0 * shape; // 参考实现的亮度缩放。
}

// 三次卷积权重：Catmull-Rom 核的四个分段，供双三次采样复用。
float ogxEclipseBicubicW0(float a) { return (1.0 / 6.0) * (a * (a * (-a + 3.0) - 3.0) + 1.0); }
float ogxEclipseBicubicW1(float a) { return (1.0 / 6.0) * (a * a * (3.0 * a - 6.0) + 4.0); }
float ogxEclipseBicubicW2(float a) { return (1.0 / 6.0) * (a * (a * (-3.0 * a + 3.0) + 3.0) + 1.0); }
float ogxEclipseBicubicW3(float a) { return (1.0 / 6.0) * (a * a * a); }
float ogxEclipseBicubicG0(float a) { return ogxEclipseBicubicW0(a) + ogxEclipseBicubicW1(a); }
float ogxEclipseBicubicG1(float a) { return ogxEclipseBicubicW2(a) + ogxEclipseBicubicW3(a); }
float ogxEclipseBicubicH0(float a) { return -1.0 + ogxEclipseBicubicW1(a) / (ogxEclipseBicubicW0(a) + ogxEclipseBicubicW1(a)); }
float ogxEclipseBicubicH1(float a) { return 1.0 + ogxEclipseBicubicW3(a) / (ogxEclipseBicubicW2(a) + ogxEclipseBicubicW3(a)); }

// Eclipse 双三次纹理采样：四个角各取一次双线性，再按卷积权重合成。
// `pixelSize` 是一像素的贴图坐标；参考实现把同样的值同时用作像素和倒数。
vec4 ogxEclipseBicubicTexture(sampler2D tex, vec2 uv, vec2 pixelSize)
{
    vec4 texelSize = vec4(pixelSize, 1.0 / pixelSize); // 与参考实现的局部变量同名同含义。
    uv = uv * texelSize.zw; // 换到像素坐标。
    vec2 iuv = floor(uv); // 整数部分。
    vec2 fuv = fract(uv); // 小数部分。
    float g0x = ogxEclipseBicubicG0(fuv.x); // 横轴左权重。
    float g1x = ogxEclipseBicubicG1(fuv.x); // 横轴右权重。
    float h0x = ogxEclipseBicubicH0(fuv.x); // 横轴左偏移。
    float h1x = ogxEclipseBicubicH1(fuv.x); // 横轴右偏移。
    float h0y = ogxEclipseBicubicH0(fuv.y); // 纵轴上偏移。
    float h1y = ogxEclipseBicubicH1(fuv.y); // 纵轴下偏移。
    vec2 p0 = (vec2(iuv.x + h0x, iuv.y + h0y) - 0.5) * texelSize.xy; // 左上样本。
    vec2 p1 = (vec2(iuv.x + h1x, iuv.y + h0y) - 0.5) * texelSize.xy; // 右上样本。
    vec2 p2 = (vec2(iuv.x + h0x, iuv.y + h1y) - 0.5) * texelSize.xy; // 左下样本。
    vec2 p3 = (vec2(iuv.x + h1x, iuv.y + h1y) - 0.5) * texelSize.xy; // 右下样本。
    return ogxEclipseBicubicG0(fuv.y) * (g0x * textureLod(tex, p0, 0.0) + g1x * textureLod(tex, p1, 0.0))
         + ogxEclipseBicubicG1(fuv.y) * (g0x * textureLod(tex, p2, 0.0) + g1x * textureLod(tex, p3, 0.0)); // 参考实现的合成顺序。
}

// 带圆形噪声偏移的双三次采样：用于体积云或天空盒旋转采样。
vec4 ogxEclipseBicubicTextureOffset(sampler2D tex, vec2 uv, float noise, float scale, vec2 pixelSize)
{
    float offsets = noise * (2.0 * OGX_PI); // 噪声转角度。
    vec2 circleOffsets = vec2(sin(offsets), cos(offsets)) * scale; // 单位圆偏移。
    vec4 texelSize = vec4(pixelSize, 1.0 / pixelSize); // 与参考实现相同的局部变量。
    uv = (uv + texelSize.xy) * texelSize.zw; // 先加一像素再换到像素坐标。
    vec2 iuv = floor(uv + circleOffsets); // 整数部分加偏移。
    vec2 fuv = fract(uv + circleOffsets); // 小数部分加偏移。
    float g0x = ogxEclipseBicubicG0(fuv.x); // 横轴左权重。
    float g1x = ogxEclipseBicubicG1(fuv.x); // 横轴右权重。
    float h0x = ogxEclipseBicubicH0(fuv.x); // 横轴左偏移。
    float h1x = ogxEclipseBicubicH1(fuv.x); // 横轴右偏移。
    float h0y = ogxEclipseBicubicH0(fuv.y); // 纵轴上偏移。
    float h1y = ogxEclipseBicubicH1(fuv.y); // 纵轴下偏移。
    vec2 p0 = (vec2(iuv.x + h0x, iuv.y + h0y) - 0.5) * texelSize.xy; // 左上样本。
    vec2 p1 = (vec2(iuv.x + h1x, iuv.y + h0y) - 0.5) * texelSize.xy; // 右上样本。
    vec2 p2 = (vec2(iuv.x + h0x, iuv.y + h1y) - 0.5) * texelSize.xy; // 左下样本。
    vec2 p3 = (vec2(iuv.x + h1x, iuv.y + h1y) - 0.5) * texelSize.xy; // 右下样本。
    return ogxEclipseBicubicG0(fuv.y) * (g0x * textureLod(tex, p0, 0.0) + g1x * textureLod(tex, p1, 0.0))
         + ogxEclipseBicubicG1(fuv.y) * (g0x * textureLod(tex, p2, 0.0) + g1x * textureLod(tex, p3, 0.0)); // 与不带偏移版相同的合成顺序。
}

// Eclipse 球面方向转等距柱状坐标：经度用负方向，纬度用高度角。
vec2 ogxEclipseSphereToCarte(vec3 dir)
{
    float lonlat = clamp(atan(-dir.x, -dir.z), -OGX_PI, OGX_PI); // 经度。
    return vec2(lonlat * (0.5 / OGX_PI) + 0.5, asin(dir.y) * (1.0 / OGX_PI) + 0.5); // 映射到零到一。
}

// Eclipse 天空盒查表：先转经纬度，再压到天空盒左上角的一块 256 像素区域。
vec3 ogxEclipseSkyFromTex(vec3 pos, sampler2D tex, vec2 pixelSize)
{
    vec2 p = ogxEclipseSphereToCarte(pos); // 球面坐标。
    vec2 clampUV = vec2(1.0); // 允许的最大范围。
    p = clamp(p * 2.0 - 1.0, -clampUV, clampUV) * 0.5 + 0.5; // 压缩到合法范围。
    return textureLod(tex, p * pixelSize * 256.0 + vec2(18.5, 1.5) * pixelSize, 0.0).rgb; // 固定偏移与缩放。
}

// Eclipse 云层查表：从天空盒右侧的云图取颜色。
vec4 ogxEclipseSkyCloudsFromTex(vec3 pos, sampler2D tex, vec2 pixelSize)
{
    vec2 p = ogxEclipseSphereToCarte(pos); // 球面坐标。
    vec2 uv = clamp(p, 0.0, 1.0) * pixelSize * 256.0 + vec2(18.5 + 257.0, 1.5) * pixelSize; // 云图偏移。
    return textureLod(tex, uv, 0.0); // 双线性采样。
}

// Eclipse 模糊云层查表：接口保留 `scaler`，参考实现当前没有使用它。
vec4 ogxEclipseSkyCloudsFromTexBlur(vec3 pos, sampler2D tex, vec2 pixelSize, float scaler)
{
    vec2 p = ogxEclipseSphereToCarte(pos); // 球面坐标。
    vec2 scaleA = pixelSize * 256.0; // 天空盒区域缩放。
    vec2 scaleB = vec2(18.5 + 257.0, 1.5) * pixelSize; // 云图偏移。
    vec2 uv = clamp(p, 0.0, 1.0) * scaleA + scaleB; // 与参考实现相同的采样位置。
    return textureLod(tex, uv, 0.0); // `scaler` 在原程序里也未参与计算。
}

// Eclipse 带粗糙度的云层查表：越粗糙，天顶附近的云越向中心压缩。
vec4 ogxEclipseSkyCloudsFromTexLod(vec3 pos, sampler2D tex, vec2 pixelSize, float roughness)
{
    vec2 p = ogxEclipseSphereToCarte(pos); // 球面坐标。
    roughness = 1.0 - pow(1.0 - roughness, 3.0); // 参考实现的粗糙度重整。
    float y = min(max(p.y - 0.5, 0.0) * 50.0, 1.0); // 只在天顶附近生效。
    p = mix(p, (p - 0.5) * (1.0 - roughness) + 0.5, y); // 向中心压缩。
    vec2 clampUV = vec2(1.0); // 合法范围。
    p = clamp(p * 2.0 - 1.0, -clampUV, clampUV) * 0.5 + 0.5; // 压缩到合法范围。
    vec2 uv = p * pixelSize * 256.0 + vec2(18.5 + 257.0, 1.5) * pixelSize; // 云图坐标。
    return textureLod(tex, uv, 0.0); // 双线性采样。
}

// Eclipse 体积雾查表：从天空盒中间偏右的区域取体积雾颜色。
vec4 ogxEclipseVolumetricsFromTex(vec3 pos, sampler2D tex, vec2 pixelSize, float lod)
{
    vec2 p = ogxEclipseSphereToCarte(pos); // 球面坐标。
    p = clamp(p, 0.0, 1.0); // 夹到合法范围。
    vec2 uv = p * pixelSize * 256.0 + vec2(256.0 - 256.0 * 0.12, 1.5) * pixelSize; // 体积雾区域偏移。
    return textureLod(tex, uv, lod); // 按粗糙度取层级。
}

// Eclipse 大气积分：沿视线固定步数积分瑞利、米氏与臭氧，输出日月散射与透过率。
// `pid` 返回行星交点参数，`transmittance` 返回视线透过率；两个输出都与参考实现相同。
vec3 ogxEclipseCalculateAtmosphere(vec3 background, vec3 viewVector, vec3 upVector, vec3 sunVector,
    vec3 moonVector, float eyeAltitude, float cameraY, vec3 sunColorBase, vec3 moonColorBase,
    vec3 coefficientRayleigh, vec3 coefficientMie, vec3 coefficientOzone,
    int iSteps, float noise, float groundReferenceHeight, bool skyGround, bool customMoonRotation,
    bool twilightForest, out vec2 pid, out vec3 transmittance, float planetRadius,
    float atmosphereRadius, vec2 scaleHeights)
{
    const int jSteps = 4; // 太阳与月亮阴影的固定步数。
    const float rLOG2 = 1.44269504089; // 以二为底的指数换底常数。
    float atmosphereRadiusSquared = atmosphereRadius * atmosphereRadius; // 大气顶半径平方。
    vec2 inverseScaleHeights = 1.0 / scaleHeights; // 标高倒数。
    vec2 scaledPlanetRadius = planetRadius * inverseScaleHeights; // 参考实现的缩放半径。

    float planetGround; // 行星地面在地平线附近的暗化。
    if (skyGround) // 使用与参考实现相同的云层参考高度暗化。
    {
        float heightRelativeToClouds = clamp(1.0 - max(cameraY - groundReferenceHeight, 0.0) / 100.0, 0.0, 1.0); // 相机相对云层高度。
        planetGround = mix(exp(-1.0 * pow(max(-viewVector.y * 10.0 + 0.1, 0.0), 2.0)),
            exp(-100.0 * pow(max(-viewVector.y * 5.0 + 0.1, 0.0), 2.0)), heightRelativeToClouds); // 两段指数的混合。
    }
    else
    {
        planetGround = pow(clamp(viewVector.y + 1.0, 0.0, 1.0), 2.0); // 没有云层时直接按视线高度压暗。
    }
    float groundDarkening = max(planetGround * 0.7 + 0.3, clamp(sunVector.y * 2.0, 0.0, 1.0)); // 地面与太阳高度的较大者。

    vec3 viewPos = (planetRadius + 1.0 + max(eyeAltitude - 300.0, 0.0)) * upVector; // 相机在大气里的位置。

    vec2 atmosphereHit = ogxRaySphereIntersection(viewPos, viewVector, atmosphereRadius); // 求大气顶交点。
    float atmosphereNear = atmosphereHit.x; // 到大气顶交点的近参数。
    float atmosphereFar = atmosphereHit.y; // 到大气顶交点的远参数。
    if (atmosphereFar < 0.0) // 视线完全离开大气。
    {
        transmittance = vec3(1.0); // 没有大气就没有衰减。
        pid = vec2(0.0); // 没有行星交点。
        return vec3(0.0); // 天空是黑的。
    }

    vec2 planetHit = ogxRaySphereIntersection(viewPos, viewVector, planetRadius * 0.998); // 求行星交点。
    float planetNear = planetHit.x; // 行星交点的近参数。
    float planetFar = planetHit.y; // 行星交点的远参数。
    bool planetIntersected = planetFar > 0.0; // 是否撞到行星。
    pid = vec2(planetNear, planetFar); // 返回行星交点参数。

    vec2 stepRange = vec2((planetIntersected && planetNear < 0.0) ? planetFar : max(atmosphereNear, 0.0),
        (planetIntersected && planetNear > 0.0) ? planetNear : atmosphereFar); // 参考实现的可见段。
    float stepSize = (stepRange.y - stepRange.x) * (1.0 / float(iSteps)); // 每步长度。
    vec3 increment = viewVector * stepSize; // 每步位移。
    vec3 position = viewVector * stepRange.x + viewPos; // 起点。
    position += increment * (0.34 * noise); // 抖动起点。

    vec2 phaseSun = ogxEclipseSkyPhase(dot(viewVector, sunVector), 0.8); // 太阳相函数。
    vec2 phaseMoon = ogxEclipseSkyPhase(dot(viewVector, moonVector), 0.8); // 月亮相函数。

    if (customMoonRotation) // 自定义月亮轨道会算月食暗化。
    {
        float eclipseDarkness = smoothstep(0.005, 0.08, length(sunVector - moonVector)); // 日月距离。
        phaseSun *= mix(1.0, eclipseDarkness, smoothstep(-1.0, 0.175, viewVector.y)); // 低空暗化更强。
    }

    vec3 scatteringSun = vec3(0.0); // 太阳散射。
    vec3 scatteringMoon = vec3(0.0); // 月亮散射。
    vec3 scatteringAmbient = vec3(0.0); // 环境散射。
    transmittance = vec3(1.0); // 视线透过率从全通开始。

    float highSun = clamp(pow(sunVector.y + 0.6, 5.0), 0.0, 1.0) * 3.0; // 高空太阳让日出少一点蓝。
    float lowSun = clamp(((1.0 - abs(sunVector.y)) * 3.0) - highSun, 1.0, 2.0); // 低空太阳让日落更蓝。

    if (twilightForest) lowSun = 2.5; // 暮色森林固定值，与参考实现相同。

    for (int i = 0; i < iSteps; ++i, position += increment) // 逐段积分。
    {
        vec3 density = ogxEclipseSkyDensity(length(position), planetRadius, scaleHeights); // 三种介质密度。
        if (density.y > 1e35) break; // 数值爆掉时提前停止。
        vec3 stepAirmass = density * stepSize; // 本段光学路径。
        vec3 stepOpticalDepth = coefficientRayleigh * stepAirmass.x + coefficientMie * stepAirmass.y + coefficientOzone * stepAirmass.z; // 本段光学厚度。
        vec3 stepTransmittance = exp2(-stepOpticalDepth * rLOG2); // 本段透过率。
        vec3 stepTransmittedFraction = clamp((stepTransmittance - 1.0) / -stepOpticalDepth, 0.0, 1.0); // 本段可散射比例。
        vec3 stepScatteringVisible = transmittance * stepTransmittedFraction; // 可见散射。

        vec3 sunAirmass = ogxEclipseSkyAirmassRay(position, sunVector, float(jSteps), planetRadius, scaleHeights, atmosphereRadius); // 到太阳的三种介质路径。
        vec3 moonAirmass = ogxEclipseSkyAirmassRay(position, moonVector, float(jSteps), planetRadius, scaleHeights, atmosphereRadius); // 到月亮的三种介质路径。
        vec3 sunOpticalDepth = coefficientRayleigh * sunAirmass.x + coefficientMie * sunAirmass.y + coefficientOzone * sunAirmass.z; // 到太阳的光学厚度。
        vec3 moonOpticalDepth = coefficientRayleigh * moonAirmass.x + coefficientMie * moonAirmass.y + coefficientOzone * moonAirmass.z; // 到月亮的光学厚度。

        vec3 sunScattering = coefficientRayleigh * stepAirmass.x * phaseSun.x + coefficientMie * stepAirmass.y * phaseSun.y; // 太阳瑞利与米氏散射。
        vec3 moonScattering = coefficientRayleigh * stepAirmass.x * phaseMoon.x + coefficientMie * stepAirmass.y * phaseMoon.y; // 月亮瑞利与米氏散射。
        if (skyGround) // 参考实现的天空地面分支只影响太阳项。
        {
            scatteringSun += sunScattering * stepScatteringVisible * exp2(-sunOpticalDepth * rLOG2) * planetGround;
        }
        else
        {
            scatteringSun += sunScattering * stepScatteringVisible * exp2(-sunOpticalDepth * rLOG2);
        }
        scatteringMoon += moonScattering * stepScatteringVisible * exp2(-moonOpticalDepth * rLOG2);
        scatteringAmbient += (coefficientRayleigh * stepAirmass.x + coefficientMie * stepAirmass.y) * stepScatteringVisible * lowSun;
        transmittance *= stepTransmittance; // 累积透过率。
    }

    return scatteringAmbient * background + scatteringSun * sunColorBase + scatteringMoon * moonColorBase * 0.5; // 参考实现的合成。
}

// Eclipse 极光哈希：一维输入打散成零到一。
float ogxEclipseAuroraHash(float p)
{
    p = fract(p * 0.1031); // 先压到小数。
    p *= p + 33.33; // 二次项。
    p *= p + p; // 再乘两倍。
    return fract(p); // 取小数。
}

// 极光二维旋转矩阵。
mat2 ogxEclipseAuroraRotation(float angle)
{
    float c = cos(angle); // 余弦。
    float s = sin(angle); // 正弦。
    return mat2(c, s, -s, c); // 按参考实现的列顺序。
}

// 三角波：把任意输入压到零点零一到零点四九之间。
float ogxEclipseAuroraTri(float x)
{
    return clamp(abs(fract(x) - 0.5), 0.01, 0.49); // 参考实现的范围。
}

// 二维三角波对：第二分量是第一分量与纵轴再次组合。
vec2 ogxEclipseAuroraTri2(vec2 p)
{
    float triX = ogxEclipseAuroraTri(p.x); // 横向三角波。
    float triY = ogxEclipseAuroraTri(p.y); // 纵向三角波。
    return vec2(triX + triY, ogxEclipseAuroraTri(triX + p.y)); // 参考实现的组合。
}

// 行向量乘矩阵：GLSL 的 `p *= m` 是行向量约定，和常见的矩阵乘向量相反。
vec2 ogxEclipseAuroraRowMul(vec2 p, mat2 m)
{
    return vec2(m[0].x * p.x + m[1].x * p.y, m[0].y * p.x + m[1].y * p.y); // 按列展开，避免转置错误。
}

// 极光分形噪声：三层三角波，逐层缩放与旋转。
float ogxEclipseAuroraTriNoise2d(vec2 p, float time)
{
    float z = 1.8; // 第一层缩放。
    float z2 = 2.5; // 第二层缩放。
    float rz = 0.0; // 累加结果。
    p = ogxEclipseAuroraRowMul(p, ogxEclipseAuroraRotation(p.x * 0.06)); // 初始旋转。
    vec2 bp = p; // 备份坐标。
    mat2 rotation = ogxEclipseAuroraRotation(time * 0.06); // 时间旋转。
    mat2 m2 = mat2(0.95534, 0.29552, -0.29552, 0.95534); // 参考实现的固定旋转。
    for (int i = 0; i < 3; i++) // 三层。
    {
        vec2 dg = ogxEclipseAuroraTri2(bp * 1.75) * 0.75; // 三角波偏移。
        dg = ogxEclipseAuroraRowMul(dg, rotation); // 旋转偏移。
        p -= dg / z2; // 坐标扰动。
        bp *= 1.3; // 频率放大。
        z2 *= 0.45; // 下一层缩放。
        z *= 0.42; // 权重衰减。
        p *= 1.21 + (rz - 1.0) * 0.02; // 参考实现的比例。
        rz += ogxEclipseAuroraTri(p.x + ogxEclipseAuroraTri(p.y)) * z; // 累加一层。
        p = ogxEclipseAuroraRowMul(p, mat2(-0.95534, -0.29552, 0.29552, -0.95534)); // 参考实现的 `p *= -m2`。
    }
    return clamp(1.0 / pow(rz * 29.0, 1.6), 0.0, 0.55); // 参考实现的收尾。
}

// Eclipse 极光主体：沿视线取样，用三角噪声生成幕帘与颜色。
// `moonY`/`sunY` 决定月亮与太阳对极光的压制，`lut` 选择是否使用六倍步长。
vec3 ogxEclipseAurora(vec3 dir, int samples, float noise, float moonY, float sunY, float time,
    vec3 background, float amount, float brightness, vec3 auroraColor, bool moonLight, bool lut)
{
    vec3 col = vec3(0.0); // 幕帘累加。
    vec3 avgCol = vec3(0.0); // 平均色。
    float hash = 0.05 * noise; // 每像素抖动。
    float fade = dir.y * 2.0 + 0.4; // 高度淡出。
    float atmosphereGround = 1.0 - exp2(-50.0 * pow(clamp(dir.y + 0.025, 0.0, 1.0), 2.0)); // 地平线附近压暗。
    float mult = lut ? 6.0 : 3.0; // LUT 模式采样更疏。
    for (int i = 0; i < samples; i++) // 逐层幕帘。
    {
        float mI = mult * float(i); // 当前层高度。
        float of = hash * smoothstep(0.0, 12.0, mI); // 抖动。
        float pt = (0.8 + pow(mI, 1.4) * 0.0016) / fade - of; // 采样半径。
        vec3 bpos = pt * dir; // 采样位置。
        float rzt = ogxEclipseAuroraTriNoise2d(bpos.zx, time); // 三角噪声。
        vec3 col2 = (sin(auroraColor + mI * 0.063) * 0.5 + 0.5) * rzt; // 当前层颜色。
        avgCol = mix(avgCol, col2, 0.1); // 参考实现的滑动平均。
        col += avgCol * exp2(-mI * 0.05 - 2.5); // 高度衰减。
    }
    vec3 aurora = 14.5 * pow(col, vec3(1.45)); // 参考实现的强化曲线。
    if (moonLight) aurora *= smoothstep(0.1, 0.0, moonY); // 月亮模式下被月光压制。
    aurora *= smoothstep(0.0, -0.1, sunY); // 太阳升起后消失。
    return aurora * atmosphereGround * amount * brightness; // 叠加到背景。
}

// Eclipse 实时大气入口：参考签名把两个输出放在第 6、7 位，库的主函数放在末尾。
// 这里按参考顺序转发，调用方不需要知道库内部的重排。
vec3 ogxItxCalculateAtmosphere(vec3 background, vec3 viewVector, vec3 upVector,
    vec3 sunVector, vec3 moonVector, out vec2 pid, out vec3 transmittance,
    int iSteps, float noise, float eyeAltitude, float cameraY, vec3 sunColorBase,
    vec3 moonColorBase, vec3 coefficientRayleigh, vec3 coefficientMie,
    vec3 coefficientOzone, float groundReferenceHeight, bool skyGround,
    bool customMoonRotation, bool twilightForest, float planetRadius, float atmosphereRadius,
    vec2 scaleHeights)
{
    return ogxEclipseCalculateAtmosphere(background, viewVector, upVector, sunVector, moonVector,
        eyeAltitude, cameraY, sunColorBase, moonColorBase, coefficientRayleigh, coefficientMie,
        coefficientOzone, iSteps, noise, groundReferenceHeight, skyGround, customMoonRotation,
        twilightForest, pid, transmittance, planetRadius, atmosphereRadius, scaleHeights);
}

#endif
