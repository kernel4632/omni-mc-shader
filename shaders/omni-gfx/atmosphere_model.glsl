/*
生成文件：大气查表模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库预计算大气查表模块：坐标映射、透过率、组合散射、辐照度与天空辐射。
调用位置：任何使用论文式预计算大气贴图的程序；Minecraft 光影由
    `/omni-gfx/atmosphere_model.glsl` 引入，`rendering/sky/atmosphere_model.glsl` 只填常数与贴图。
可复制示例：`OgxAtmosphereModel model = ...;` 由调用方填好行星常数与贴图尺寸，再调用
    `ogxAtmoSkyRadiance` 查某个方向的天空辐射。
设计原因与取舍：
    本模块不读加载器输入、选项宏与中间画面；大气常数由调用方填进结构体，预计算贴图由采样器参数传入。
    读表而不是实时积分，代价与分辨率无关；所有函数只做几何与查表，公式与 iterationT 逐行一致。
    结构体字段沿用旧适配层的下划线命名：宿主有几十处逐字段赋值，改名会把风险推到调用点。
*/
#ifndef OGX_ATMOSPHERE_MODEL_INCLUDED
#define OGX_ATMOSPHERE_MODEL_INCLUDED

// 球面几何与相位函数来自大气模块，亮度与夹紧来自数学模块。
#include "/omni-gfx/atmosphere.glsl"
#include "/omni-gfx/math.glsl"
// 一次查表需要的全部常数与贴图尺寸；数值由宿主按原程序填写，本模块不保存默认值。
struct OgxAtmosphereModel
{
    float bottom_radius; // 行星底半径，越过它就算被地面挡住。
    float top_radius; // 大气层顶半径，视线到这里离开大气。
    float sun_angular_radius; // 太阳视半径，日落时用它对太阳方向做渐隐。
    float mie_phase_g; // 米氏相位的前向集中程度。
    float mu_s_min; // 太阳高度角的查表下限。
    vec3 solar_irradiance; // 太阳辐照度，决定大气散射的基准亮度。
    vec3 rayleigh_scattering; // 瑞利散射系数，蓝光最强，天空因此偏蓝。
    vec3 mie_scattering; // 米氏散射系数，气溶胶造成太阳附近的白晕。
    float density_rayleigh; // 瑞利密度剖面的指数系数。
    float density_mie; // 米氏密度剖面的指数系数。
    float absorption_width; // 臭氧三角剖面的转折高度。
    vec4 density_absorption; // 臭氧剖面分段线性系数。
    float transmittance_width; // 透过率子图宽度，单位像素。
    float transmittance_height; // 透过率子图高度。
    float scattering_r; // 散射子图的半径方向尺寸。
    float scattering_mu; // 散射子图的高度角方向尺寸。
    float scattering_mu_s; // 散射子图的太阳高度角方向尺寸。
    float scattering_nu; // 散射子图的视线与太阳夹角方向尺寸。
    float combined_width; // 拼合后大图宽度。
    float combined_height; // 拼合后大图高度。
    float combined_depth; // 拼合后大图深度。
    float irradiance_width; // 辐照度子图宽度。
    float irradiance_height; // 辐照度子图高度。
};

// 色适应矩阵：把物理辐照度的三刺激值转到本项目使用的原色空间；与 iterationT 一致。
const mat3 OGX_ATMO_LMS = mat3(1.6858, -0.4624, -0.0069, -0.0374, 1.0598, -0.0742, -0.0283, -0.1119, 1.0491);

// 把半径夹进大气层范围内，越界时按最近的边界算。
float ogxAtmoClampRadius(OgxAtmosphereModel m, float r)
{
    return ogxClampRadius(r, m.bottom_radius, m.top_radius); // 边界由调用方提供。
}

// 视线到大气层顶的距离，解视线与顶球面的方程取远根。
float ogxAtmoDistanceToTop(OgxAtmosphereModel m, float r, float mu)
{
    return ogxSphereDistanceToTop(r, mu, m.top_radius); // 球面几何在通用库，层顶半径在这里传入。
}

// 视线到大气层底的距离，解视线与底球面的方程取近根。
float ogxAtmoDistanceToBottom(OgxAtmosphereModel m, float r, float mu)
{
    return ogxSphereDistanceToBottom(r, mu, m.bottom_radius); // 层底半径在这里传入。
}

// 判断一条朝下的视线是否真的打到地面球。
bool ogxAtmoRayIntersectsGround(OgxAtmosphereModel m, float r, float mu)
{
    return ogxSphereRayIntersectsGround(r, mu, m.bottom_radius); // 与地面球的相交判断在通用库。
}

// 瑞利与米氏密度剖面：以二为底的指数衰减，系数已经积分好。
float ogxAtmoDensityRayleighMie(float expScale, float altitude)
{
    return ogxExponentialDensity(expScale, altitude); // 指数密度剖面在通用库。
}

// 臭氧密度剖面：在转折高度以下是一段斜线，以上是另一段斜线。
float ogxAtmoDensityAbsorption(float width, vec4 profile, float altitude)
{
    return ogxAbsorptionDensity(width, profile, altitude); // 两段线性剖面在通用库。
}

// 把零到一的比例映射到贴图坐标的像素中心，避免采到子图交界。
float ogxAtmoTextureCoord(float x, float textureSize)
{
    return ogxTexelCenterCoord(x, textureSize); // 像素中心换算在通用库。
}

// 把子图内部的比例映射到拼合大图上的坐标，子图在大图里也内缩半像素。
float ogxAtmoCombinedTextureCoord(float x, float originalTextureSize, float combinedTextureSize)
{
    return ogxSubTextureCoord(x, originalTextureSize, combinedTextureSize); // 拼图坐标换算在通用库。
}

// 把半径与几个角度换成散射三维贴图的四维坐标：前三维是坐标，第四维留给上层插值。
vec4 ogxAtmoScatteringUvwz(OgxAtmosphereModel m, float r, float mu, float mu_s, float nu, bool rayRMuIntersectsGround)
{
    float H = sqrt(m.top_radius * m.top_radius - m.bottom_radius * m.bottom_radius); // 大气层顶相对地面的水平距离。
    float rho = ogxSafeSqrt(r * r - m.bottom_radius * m.bottom_radius); // 相机到地心的水平投影。
    float u_r = ogxAtmoCombinedTextureCoord(rho / H, m.scattering_r, m.combined_depth); // 半径方向落到深度坐标。
    float r_mu = r * mu; // 半径乘高度角余弦，判别式里反复用到。
    float discriminant = r_mu * r_mu - r * r + m.bottom_radius * m.bottom_radius; // 是否打到地面的判别式。
    float u_mu; // 高度角方向的坐标，下面分两种情形算。
    if (rayRMuIntersectsGround) // 打到地面：用近根，坐标落在下半段。
    {
        float d = -r_mu - ogxSafeSqrt(discriminant); // 到地面的距离。
        float d_min = r - m.bottom_radius; // 距离下限。
        float d_max = rho; // 距离上限。
        u_mu = 0.5 - 0.5 * ogxAtmoTextureCoord(float(d_max != d_min) * (d - d_min) / (d_max - d_min), m.scattering_mu / 2.0); // 映射到下半张子图。
    }
    else // 没打到地面：用远根，坐标落在上半段。
    {
        float d = -r_mu + ogxSafeSqrt(discriminant + H * H); // 到层顶的距离。
        float d_min = m.top_radius - r; // 距离下限。
        float d_max = rho + H; // 距离上限。
        u_mu = 0.5 + 0.5 * ogxAtmoTextureCoord((d - d_min) / (d_max - d_min), m.scattering_mu / 2.0); // 映射到上半张子图。
    }
    float d = ogxAtmoDistanceToTop(m, m.bottom_radius, mu_s); // 太阳高度角对应的层顶距离。
    float d_min = m.top_radius - m.bottom_radius; // 距离下限。
    float d_max = H; // 距离上限。
    float a = (d - d_min) / (d_max - d_min); // 太阳高度角的归一化距离。
    float D = ogxAtmoDistanceToTop(m, m.bottom_radius, m.mu_s_min); // 查表下限对应的距离。
    float A = (D - d_min) / (d_max - d_min); // 下限的归一化距离。
    float u_mu_s = ogxAtmoTextureCoord(max(1.0 - a / A, 0.0) / (1.0 + a), m.scattering_mu_s); // 非线性映射到太阳高度角坐标。
    float u_nu = (nu + 1.0) / 2.0; // 视线与太阳夹角从负一到一转成零到一。
    return vec4(u_nu, u_mu_s, u_mu, u_r); // 返回四维坐标，供上层做夹角方向插值。
}

// 把半径与高度角换成透过率子图坐标。
vec2 ogxAtmoTransmittanceUv(OgxAtmosphereModel m, float r, float mu)
{
    float H = sqrt(m.top_radius * m.top_radius - m.bottom_radius * m.bottom_radius); // 大气层顶相对地面的水平距离。
    float rho = ogxSafeSqrt(r * r - m.bottom_radius * m.bottom_radius); // 相机到地心的水平投影。
    float d = ogxAtmoDistanceToTop(m, r, mu); // 到层顶的距离。
    float d_min = m.top_radius - r; // 距离下限。
    float d_max = rho + H; // 距离上限。
    float x_mu = (d - d_min) / (d_max - d_min); // 高度角方向的归一化位置。
    float x_r = rho / H; // 半径方向的归一化位置。
    return vec2(ogxAtmoCombinedTextureCoord(x_mu, m.transmittance_width, m.combined_width), // 横坐标是高度角方向。
                  ogxAtmoCombinedTextureCoord(x_r, m.transmittance_height, m.combined_height)); // 纵坐标是半径方向。
}

// 查到层顶的透过率：透过率存在拼合大图的同一深度层上。
vec3 ogxAtmoTransmittanceToTop(OgxAtmosphereModel m, sampler3D lut, float r, float mu)
{
    vec2 uv = ogxAtmoTransmittanceUv(m, r, mu); // 先算子图坐标。
    return vec3(textureLod(lut, vec3(uv, 32.5 / 33.0), 0.0)); // 读固定深度层，取三通道颜色。
}

// 两点之间的透过率：由两端到层顶的透过率相除得到，地面相交时用镜像方向。
vec3 ogxAtmoTransmittance(OgxAtmosphereModel m, sampler3D lut, float r, float mu, float d, bool rayRMuIntersectsGround)
{
    float r_d = ogxAtmoClampRadius(m, sqrt(d * d + 2.0 * r * mu * d + r * r)); // 终点相对地心的半径。
    float mu_d = clamp((r * mu + d) / r_d, -1.0, 1.0); // 终点处的高度角余弦。
    if (rayRMuIntersectsGround) // 打到地面时用负高度角镜像。
    {
        return min(ogxAtmoTransmittanceToTop(m, lut, r_d, -mu_d) / ogxAtmoTransmittanceToTop(m, lut, r, -mu), vec3(1.0)); // 两端相除并封顶到一。
    }
    return min(ogxAtmoTransmittanceToTop(m, lut, r, mu) / ogxAtmoTransmittanceToTop(m, lut, r_d, mu_d), vec3(1.0)); // 没打到地面直接用正高度角。
}

// 从某点朝太阳方向到层顶的透过率，太阳贴地时按太阳视半径留一段过渡。
vec3 ogxAtmoTransmittanceToSun(OgxAtmosphereModel m, sampler3D lut, float r, float mu_s)
{
    float sin_theta_h = m.bottom_radius / r; // 地平线方向的俯角正弦。
    float cos_theta_h = -sqrt(max(1.0 - sin_theta_h * sin_theta_h, 0.0)); // 地平线方向的余弦。
    return ogxAtmoTransmittanceToTop(m, lut, r, mu_s) * // 基础透过率。
        smoothstep(-sin_theta_h * m.sun_angular_radius, // 过渡带下沿。
                   sin_theta_h * m.sun_angular_radius, // 过渡带上沿。
                   mu_s - cos_theta_h); // 过渡带半宽由太阳视半径决定。
}

// 从拼合散射数据反推单次米氏散射：按通道比例还原。
vec3 ogxAtmoExtrapolatedMie(OgxAtmosphereModel m, vec4 scattering)
{
    if (scattering.r <= 0.0) return vec3(0.0); // 红通道为零说明没有数据。
    return scattering.rgb * scattering.a / scattering.r * // 按红通道比例缩放。
        (m.rayleigh_scattering.r / m.mie_scattering.r) * // 瑞利与米氏红通道比例。
        (m.mie_scattering / m.rayleigh_scattering); // 逐通道还原米氏散射。
}

// 查组合散射：先在夹角方向插值两片，再拆出单次米氏散射。
vec3 ogxAtmoCombinedScattering(OgxAtmosphereModel m, sampler3D lut, float r, float mu, float mu_s, float nu,
    bool rayRMuIntersectsGround, out vec3 singleMieScattering)
{
    vec4 uvwz = ogxAtmoScatteringUvwz(m, r, mu, mu_s, nu, rayRMuIntersectsGround); // 四维查表坐标。
    float tex_coord_x = uvwz.x * (m.scattering_nu - 1.0); // 夹角方向落在第几片。
    float tex_x = floor(tex_coord_x); // 前一片的编号。
    float frac = tex_coord_x - tex_x; // 两片之间的插值比例。
    vec3 uvw0 = vec3((tex_x + uvwz.y) / m.scattering_nu, uvwz.z, uvwz.w); // 前一片的三维坐标。
    vec3 uvw1 = vec3((tex_x + 1.0 + uvwz.y) / m.scattering_nu, uvwz.z, uvwz.w); // 后一片的三维坐标。
    vec4 combined = textureLod(lut, uvw0, 0.0) * (1.0 - frac) + textureLod(lut, uvw1, 0.0) * frac; // 两片之间线性插值。
    singleMieScattering = ogxAtmoExtrapolatedMie(m, combined); // 第四通道还原单次米氏散射。
    return vec3(combined); // 前三通道是组合散射。
}

// 查辐照度：给出某个高度朝上接到的太阳与环境辐照度。
vec3 ogxAtmoIrradiance(OgxAtmosphereModel m, sampler3D lut, float r, float mu_s)
{
    float x_r = (r - m.bottom_radius) / (m.top_radius - m.bottom_radius); // 半径方向归一化。
    float x_mu_s = mu_s * 0.5 + 0.5; // 太阳高度角从负一到一转成零到一。
    vec2 uv = vec2(ogxAtmoCombinedTextureCoord(x_mu_s, m.irradiance_width, m.combined_width), // 横坐标是高度角方向。
                       ogxAtmoCombinedTextureCoord(x_r, m.irradiance_height, m.combined_height) + m.transmittance_height / m.combined_height); // 纵坐标要跳过透过率子图。
    return vec3(textureLod(lut, vec3(uv, 32.5 / 33.0), 0.0)); // 读固定深度层的辐照度。
}

// 算某点的太阳、月亮与天空辐照度：太阳和月亮各出一份直射与一份环境。
vec3 ogxAtmoSunSkyIrradiance(OgxAtmosphereModel m, sampler3D lut, vec3 point, vec3 sunDirection, vec3 moonDirection,
    float nightBrightness, vec3 sunTint, out vec3 moonIrradiance,
    out vec3 sunSkyIrradiance, out vec3 moonSkyIrradiance)
{
    float r = length(point); // 点到地心的距离。
    float sun_mu_s = dot(point, sunDirection) / r; // 太阳方向相对当地向上的余弦。
    float moon_mu_s = dot(point, moonDirection) / r; // 月亮方向相对当地向上的余弦。
    sunSkyIrradiance = ogxAtmoIrradiance(m, lut, r, sun_mu_s) * OGX_ATMO_LMS; // 太阳侧的环境辐照度，乘色适应矩阵。
    moonSkyIrradiance = ogxAtmoIrradiance(m, lut, r, moon_mu_s) * nightBrightness * OGX_ATMO_LMS; // 月亮侧环境辐照度，按夜间亮度缩放。
    vec3 sunIrradiance = m.solar_irradiance; // 太阳直射从标准辐照度出发。
    moonIrradiance = sunIrradiance * ogxAtmoTransmittanceToSun(m, lut, r, moon_mu_s) * nightBrightness * OGX_ATMO_LMS; // 月亮直射等于太阳辐照度乘月光透过率，再按夜间亮度缩放。
    sunIrradiance *= ogxAtmoTransmittanceToSun(m, lut, r, sun_mu_s); // 太阳直射乘它自己的透过率。
    return sunIrradiance * OGX_ATMO_LMS * sunTint; // 只染太阳直射：月亮直射有独立的色温，若在这里染色会把月亮一起带偏。
}

// 算某个视线方向的天空辐射亮度：日月散射、可选的地面反弹，再乘天气修正。
vec3 ogxAtmoSkyRadiance(OgxAtmosphereModel m, sampler3D lut, vec3 camera, vec3 viewRay, vec3 sunDirection,
    vec3 moonDirection, bool horizon, vec3 rayleighTint, vec3 mieTint,
    float nightBrightness, float wetness, float skyBrightness, bool groundBounce,
    out vec3 transmittance, out bool rayRMuIntersectsGround)
{
    float r = length(camera); // 相机到地心的距离。
    float rmu = dot(camera, viewRay); // 相机位置与视线的点积。
    float distance_to_top = -rmu - sqrt(rmu * rmu - r * r + m.top_radius * m.top_radius); // 相机到层顶的负距离，正数表示相机在上方。
    if (distance_to_top > 0.0) // 相机在大气内部时把起点推到层顶。
    {
        camera = camera + viewRay * distance_to_top; // 沿视线外推到层顶。
        r = m.top_radius; // 起点半径等于层顶。
        rmu += distance_to_top; // 同步更新点积。
    }
    else if (r > m.top_radius) // 相机在层顶之外时没有大气。
    {
        transmittance = vec3(1.0); // 透过率为一。
        return vec3(0.0); // 没有散射。
    }
    float mu = rmu / r; // 起点的高度角余弦。
    float sun_mu_s = dot(camera, sunDirection) / r; // 太阳方向相对当地向上的余弦。
    float sun_nu = dot(viewRay, sunDirection); // 视线与太阳夹角余弦。
    float moon_mu_s = dot(camera, moonDirection) / r; // 月亮方向相对当地向上的余弦。
    float moon_nu = dot(viewRay, moonDirection); // 视线与月亮夹角余弦。
    rayRMuIntersectsGround = ogxAtmoRayIntersectsGround(m, r, mu); // 视线是否打到地面。
    transmittance = rayRMuIntersectsGround ? vec3(0.0) : ogxAtmoTransmittanceToTop(m, lut, r, mu); // 打到地面时透过率为零。
    vec3 sunSingleMieScattering; // 太阳侧的单次米氏散射。
    vec3 moonSingleMieScattering; // 月亮侧的单次米氏散射。
    horizon = horizon && rayRMuIntersectsGround; // 只有打到地面才考虑地平线处理。
    vec3 sunScattering = ogxAtmoCombinedScattering(m, lut, r, mu, sun_mu_s, sun_nu, horizon, sunSingleMieScattering); // 查太阳侧组合散射。
    vec3 moonScattering = ogxAtmoCombinedScattering(m, lut, r, mu, moon_mu_s, moon_nu, horizon, moonSingleMieScattering); // 查月亮侧组合散射。
    vec3 groundDiffuse = vec3(0.0); // 地面反弹的散射。
    if (groundBounce && horizon) // 只有开启地平线且视线打到地面才算。
    {
        vec3 planetSurface = camera + viewRay * ogxAtmoDistanceToBottom(m, r, mu); // 视线与地面的交点。
        float planet_r = length(planetSurface); // 交点到地心的距离。
        float planet_sun_mu_s = dot(planetSurface, sunDirection) / planet_r; // 交点处的太阳高度角余弦。
        float planet_moon_mu_s = dot(planetSurface, moonDirection) / planet_r; // 交点处的月亮高度角余弦。
        vec3 skyIrradiance = ogxAtmoIrradiance(m, lut, planet_r, planet_sun_mu_s); // 交点处的太阳侧环境辐照度。
        skyIrradiance += ogxAtmoIrradiance(m, lut, planet_r, planet_moon_mu_s) * nightBrightness; // 加上月亮侧环境辐照度。
        vec3 sunIrradiance = m.solar_irradiance * ogxAtmoTransmittanceToSun(m, lut, planet_r, planet_sun_mu_s); // 交点处的太阳直射辐照度。
        float d = distance(camera, planetSurface); // 相机到交点的距离。
        vec3 surfaceTransmittance = ogxAtmoTransmittance(m, lut, r, mu, d, rayRMuIntersectsGround); // 这段距离的透过率。
        groundDiffuse = mix(skyIrradiance * 0.1, sunIrradiance * 0.008, wetness * 0.6) * surfaceTransmittance; // 地面反弹按干湿在环境与直射之间插值。
    }
    vec3 rayleigh = (sunScattering * ogxRayleighPhase(sun_nu) // 太阳侧瑞利散射乘瑞利相位。
                     + moonScattering * ogxRayleighPhase(moon_nu) * nightBrightness) // 月亮侧同理并按夜间亮度缩放。
                     * rayleighTint; // 再按散射系数逐通道缩放瑞利散射，默认全一不改画面。
    vec3 mie = (sunSingleMieScattering * ogxMiePhase(m.mie_phase_g, sun_nu) // 太阳侧米氏散射乘米氏相位。
                + moonSingleMieScattering * ogxMiePhase(m.mie_phase_g, moon_nu) * nightBrightness) // 月亮侧同理。
                * mieTint; // 再按散射系数逐通道缩放米氏散射，默认全一不改画面。
    rayleigh = mix(rayleigh, vec3(ogxLuminance(rayleigh)) * m.solar_irradiance, wetness * 0.5); // 雨天把瑞利散射去色并按太阳谱重新染色。
    return (rayleigh + mie + groundDiffuse) * (1.0 - wetness * 0.4) * OGX_ATMO_LMS * skyBrightness; // 合成后按雨天压暗、转色适应空间，再乘天空亮度。
}

// 算相机到某个世界点之间的天空辐射亮度，体积云与平面云算空气透视时用。
vec3 ogxAtmoSkyRadianceToPoint(OgxAtmosphereModel m, sampler3D lut, vec3 camera, vec3 point, vec3 sunDirection,
    vec3 moonDirection, bool localLighting, vec3 rayleighTint, vec3 mieTint,
    float nightBrightness, float wetness, float skyBrightness, out vec3 transmittance)
{
    vec3 viewRay = normalize(point - camera); // 从相机指向目标点的方向。
    float r = length(camera); // 相机到地心的距离。
    float rmu = dot(camera, viewRay); // 相机位置与视线的点积。
    float distance_to_top = -rmu - sqrt(rmu * rmu - r * r + m.top_radius * m.top_radius); // 相机到层顶的负距离。
    if (distance_to_top > 0.0) // 相机在大气内部时把起点推到层顶。
    {
        camera = camera + viewRay * distance_to_top; // 沿视线外推到层顶。
        r = m.top_radius; // 起点半径等于层顶。
        rmu += distance_to_top; // 同步更新点积。
    }
    float mu = rmu / r; // 起点的高度角余弦。
    float sun_mu_s = dot(camera, sunDirection) / r; // 太阳方向相对当地向上的余弦。
    float sun_nu = dot(viewRay, sunDirection); // 视线与太阳夹角余弦。
    float moon_mu_s = dot(camera, moonDirection) / r; // 月亮方向相对当地向上的余弦。
    float moon_nu = dot(viewRay, moonDirection); // 视线与月亮夹角余弦。
    float d = length(point - camera); // 起点到目标点的距离。
    bool rayRMuIntersectsGround = localLighting ? ogxAtmoRayIntersectsGround(m, r, mu) : false; // 云局部光照开启时才考虑地面相交。
    transmittance = ogxAtmoTransmittance(m, lut, r, mu, d, rayRMuIntersectsGround); // 起点到目标点的透过率。
    vec3 sunSingleMieScattering; // 太阳侧单次米氏散射。
    vec3 sunScattering = ogxAtmoCombinedScattering(m, lut, r, mu, sun_mu_s, sun_nu, rayRMuIntersectsGround, sunSingleMieScattering); // 起点处太阳侧组合散射。
    vec3 moonSingleMieScattering; // 月亮侧单次米氏散射。
    vec3 moonScattering = ogxAtmoCombinedScattering(m, lut, r, mu, moon_mu_s, moon_nu, rayRMuIntersectsGround, moonSingleMieScattering); // 起点处月亮侧组合散射。
    float r_p = ogxAtmoClampRadius(m, sqrt(d * d + 2.0 * r * mu * d + r * r)); // 目标点相对地心的半径。
    float mu_p = (r * mu + d) / r_p; // 目标点处的高度角余弦。
    float sun_mu_s_p = (r * sun_mu_s + d * sun_nu) / r_p; // 目标点处的太阳高度角余弦。
    float moon_mu_s_p = (r * moon_mu_s + d * moon_nu) / r_p; // 目标点处的月亮高度角余弦。
    vec3 sunSingleMieScatteringP; // 目标点处太阳侧单次米氏散射。
    vec3 sunScatteringP = ogxAtmoCombinedScattering(m, lut, r_p, mu_p, sun_mu_s_p, sun_nu, rayRMuIntersectsGround, sunSingleMieScatteringP); // 目标点处太阳侧组合散射。
    vec3 moonSingleMieScatteringP; // 目标点处月亮侧单次米氏散射。
    vec3 moonScatteringP = ogxAtmoCombinedScattering(m, lut, r_p, mu_p, moon_mu_s_p, moon_nu, rayRMuIntersectsGround, moonSingleMieScatteringP); // 目标点处月亮侧组合散射。
    sunScattering = sunScattering - transmittance * sunScatteringP; // 两点之差的散射是这段空气的贡献。
    sunSingleMieScattering = sunSingleMieScattering - transmittance * sunSingleMieScatteringP; // 米氏散射同样相减。
    moonScattering = moonScattering - transmittance * moonScatteringP; // 月亮侧同理。
    moonSingleMieScattering = moonSingleMieScattering - transmittance * moonSingleMieScatteringP; // 月亮侧米氏同样相减。
    sunSingleMieScattering = sunSingleMieScattering * smoothstep(0.0, 0.01, sun_mu_s); // 太阳很贴地时淡出米氏散射，避免出现断带。
    moonSingleMieScattering = moonSingleMieScattering * smoothstep(0.0, 0.01, moon_mu_s); // 月亮同样处理。
    vec3 rayleigh = (sunScattering * ogxRayleighPhase(sun_nu) // 太阳侧瑞利散射。
                     + moonScattering * ogxRayleighPhase(moon_nu) * nightBrightness) // 月亮侧瑞利散射。
                     * rayleighTint; // 按散射系数逐通道缩放，默认全一不改画面。
    vec3 mie = (sunSingleMieScattering * ogxMiePhase(m.mie_phase_g, sun_nu) // 太阳侧米氏散射。
                + moonSingleMieScattering * ogxMiePhase(m.mie_phase_g, moon_nu) * nightBrightness) // 月亮侧米氏散射。
                * mieTint; // 按散射系数逐通道缩放，默认全一不改画面。
    rayleigh = mix(rayleigh, vec3(ogxLuminance(rayleigh)) * m.solar_irradiance, wetness * 0.5); // 雨天把瑞利散射去色重染。
    return (rayleigh + mie) * (1.0 - wetness * 0.4) * OGX_ATMO_LMS * skyBrightness; // 合成后按雨天压暗并转色适应空间，再乘天空亮度。
}

#endif
