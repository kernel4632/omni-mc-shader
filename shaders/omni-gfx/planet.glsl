/*
生成文件：行星模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中按效果分文件夹，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库行星模块：用解析射线画出整颗行星、光环与大气，不依赖任何宿主状态。
调用位置：末地天空与末地反射；Minecraft 光影由 `/omni-gfx/planet.glsl` 引入，
    `shaders/effects/world/end_sky.glsl` 与 `shaders/effects/world/planet.glsl` 按阶段组合。
可复制示例：`ogxPlanetEnd(color, eye, rayDir, lightDir, shadowVector, time, planetShadow, noiseTex);`
设计原因与取舍：行星半径、相机高度、时间、阴影强度与噪声贴图全部由调用方传入，库只做纯计算；
    星场与吸积盘不在这里，行星本体只负责地表、环带与大气这三段。
    旋转矩阵沿用原程序的扁平构造参数顺序，生成 GLSL 后由 GLSL 的列主序规则解释，
    与旧实现逐位一致；不要在 Slang 侧改成按列传入。
*/
#ifndef OGX_PLANET_INCLUDED
#define OGX_PLANET_INCLUDED

// 数学提供求交、圆盘剖面与色温，大气提供米氏相位与行星双向反射。
#include "/omni-gfx/common/math.glsl"
// 大气提供散射、密度剖面与天球映射。
#include "/omni-gfx/atmosphere/atmosphere.glsl"
// 行星曲率下沉：水平距离平方乘强度，模拟球面相对切面的高度亏损。
// 为什么属于行星模块：它描述行星表面的弯曲，只被地形与实体的顶点阶段使用；
// 放进通用数学会让所有模块都带一条没人用的公式。
float ogxPlanetCurvatureDrop(vec2 horizontal, float amount)
{
    float curvature = length(horizontal) / 128.0; // 一百二十八米是参考实现的基准距离。
    return curvature * curvature * amount; // 平方让近处几乎不弯，远处逐渐明显。
}


// 画一整颗行星：先与地表球求交，再叠光环与大气，最后把环带的遮挡乘回天空。
// `eye` 是相机在行星坐标系里的位置，`rayDir` 是视线，`lightDir` 是光方向。
// `shadowVector` 只用于米氏相位的观察方向，`time` 驱动行星与光环的缓慢摆动。
// `planetShadow` 是行星落在天空上的阴影强度，`noiseTex` 提供环带细缝的五层噪声。
void ogxPlanetEnd(inout vec3 color, vec3 eye, vec3 rayDir, vec3 lightDir,
    vec3 shadowVector, float time, float planetShadow, sampler2D noiseTex)
{
    const float Rground = 20e6; // 行星半径。
    const float Ratmo = 20.1e6; // 大气层顶半径。
    eye.y += Rground; // 相机抬到行星表面之上。
    eye.y += 15e6; // 再抬高，模拟远离行星的视角。
    float VdotL = dot(shadowVector, rayDir); // 视线与阳光夹角余弦，供相位使用。
    float mie = ogxMiePhase(0.8, VdotL); // 米氏相位。
    float angleX = -1.57079633 + (0.2 * sin(time + 3.0) - 0.1); // 俯仰角随时间摆动。
    mat3 eyeRotationMatrix = ogxRotationXThenY(angleX, time); // 行星视角的俯仰与偏航。
    float ringAngle = 0.008 * sin(time + 4.6); // 光环的倾角随时间轻微摆动。
    mat3 ringRotationMatrix = mat3(1.0, 0.0, 0.0,
                                           0.0, cos(ringAngle), sin(ringAngle),
                                           0.0, -sin(ringAngle), cos(ringAngle)); // 光环旋转矩阵。
    mat3 ringRotationMatrixInverse = transpose(ringRotationMatrix); // 光环旋转的逆。
    rayDir = ogxMatrix3MulPoint(eyeRotationMatrix, rayDir); // 视线转到行星坐标系。
    lightDir = ogxMatrix3MulPoint(eyeRotationMatrix, lightDir); // 光方向同样转过去。
    vec3 rayDirRing = ogxMatrix3MulPoint(ringRotationMatrix, rayDir); // 视线转到光环坐标系。
    vec3 lightDirRing = ogxMatrix3MulPoint(ringRotationMatrix, lightDir); // 光方向转到光环坐标系。
    vec3 ringOrigin = vec3(0.0, cos(ringAngle), sin(ringAngle)) * (eye.y / Rground); // 光环所在平面的原点。
    const vec2 ringRadius = vec2(1.6, 2.6); // 光环内外半径，两个采样点共用一份。
    vec3 surface = vec3(0.0); // 行星表面与光环累积的颜色。
    vec2 groundIntersection = ogxRaySphereIntersection(eye, rayDir, Rground); // 与行星地表求交。
    vec2 topAtmoIntersection = ogxRaySphereIntersection(eye, rayDir, Ratmo); // 与大气层顶求交。
    vec3 surfacePos = rayDir * groundIntersection.x; // 地表交点位置。
    vec3 surfaceNormal = normalize(surfacePos + vec3(0.0, eye.y, 0.0)); // 地表法线，由球心指向交点。
    if (groundIntersection.y > 0.0) // 射线打到行星本体。
    {
        color *= 0.0; // 本体完全遮住后面的天光。
        vec3 surfaceAlbedo = vec3(0.98, 0.87, 0.55); // 行星表面底色，偏暖白。
        surface = ogxPlanetBrdf(surfaceAlbedo, surfaceNormal, -rayDir, lightDir); // 算地表着色。
        vec3 origin = ringOrigin + surfacePos / Rground; // 光环采样的起点。
        vec3 rayPos = ogxRayPlaneIntersection(origin, lightDirRing, vec3(0.0, 0.0, 1.0)); // 沿光方向与光环平面求交。
        float rayRadius = length(rayPos); // 交点到光环中心的半径。
        if (rayRadius > ringRadius.x && rayRadius < ringRadius.y && dot(rayPos - origin, lightDirRing) > 0.0) // 落在环带内且朝光一侧。
        {
            float ringNoise = ogxPlanetRingNoise(rayRadius * 0.5 + 0.69, noiseTex); // 五层噪声叠出环带细缝。
            surface *= exp(-pow(ogxSaturate(ringNoise) * 1.5, 3.0) * smoothstep(ringRadius.x, ringRadius.x * 1.1, rayRadius)); // 噪声把环带压出缝隙。
        }
        float UdotN = ogxSaturate(dot(ringRotationMatrixInverse[2], surfaceNormal)); // 光环上表面法线与地表法线夹角。
        float DdotN = ogxSaturate(dot(-ringRotationMatrixInverse[2], surfaceNormal)); // 光环下表面同理。
        float OLdotN = ogxSaturate(dot(ogxMatrix3MulPoint(ringRotationMatrixInverse, normalize(vec3(-lightDir.xy, 0.0))), surfaceNormal)); // 光线在环面上的投影与法线夹角。
        float ringLighting = ogxDiscProfile(UdotN, 1.2, 1.5) * (1.0 - ogxDiscProfile(UdotN, 3.4, 0.3)); // 上表面环带光照。
        ringLighting += ogxDiscProfile(DdotN, 1.2, 1.5) * (1.0 - ogxDiscProfile(DdotN, 3.4, 0.3)); // 下表面环带光照。
        ringLighting *= 1.0 - ogxDiscProfile(OLdotN, 0.7, 1.3); // 被行星自身挡住的部分去掉。
        surface += surfaceAlbedo * (1.5e-4 + ringLighting * 0.01); // 环带光叠到地表上。
    }
    if (topAtmoIntersection.y > 0.0) // 射线经过大气层。
    {
        float isGround = step(0.0, groundIntersection.y); // 是否打到地面。
        float thickness = (topAtmoIntersection.y - topAtmoIntersection.x - (groundIntersection.y - groundIntersection.x) * isGround) * 1e-7; // 大气层内的光学厚度。
        float topAtmoMie = mie * thickness * thickness; // 米氏散射。
        topAtmoMie *= mix(1.0, smoothstep(0.9, 0.4, dot(surfaceNormal, normalize(eye))), isGround); // 打到地面时按视线角度衰减。
        surface += topAtmoMie * vec3(0.65, 0.7, 1.0); // 大气偏冷蓝。
    }
    color += surface * 0.6; // 地表与大气叠加到画面。
    float inRing = ogxSaturate(abs(ringAngle) * 3000.0 - 0.8); // 当前是否正对环面。
    float ring = 0.0; // 环带的亮度。
    float transmittance = 1.0; // 环带留下的透过率。
    if (rayDirRing.z * ringAngle < 0.0) // 视线穿过环面。
    {
        vec3 origin = vec3(0.0, cos(ringAngle), sin(ringAngle)) * (eye.y / Rground); // 环面原点。
        vec3 ringPos = ogxRayPlaneIntersection(origin, rayDirRing, vec3(0.0, 0.0, 1.0)); // 视线与环面求交。
        float rayRadius = length(ringPos); // 交点到环心半径。
        if (rayRadius > ringRadius.x && rayRadius < ringRadius.y) // 落在环带内。
        {
            float ringNoise = ogxPlanetRingNoise(rayRadius * 0.5 + 0.69, noiseTex); // 五层噪声叠出环带细缝。
            ring += pow(ogxSaturate(ringNoise) * 1.5, 3.0); // 噪声得到环带形状。
            ring *= smoothstep(ringRadius.x, ringRadius.x * 1.1, rayRadius); // 内边缘渐入。
            if (ringPos.y < 0.0 && groundIntersection.y > 0.0) // 交点在环面下方且视线打到地面。
            {
                ring *= 0.0; // 被行星本体挡住，环带不显示。
            }
            else
            {
                transmittance *= exp2(-ring * 3.0); // 否则环带按厚度吃掉一部分透过。
            }
            float d = length(cross(lightDirRing, ringPos)); // 交点到光方向的垂距。
            ring *= 0.98 * max(smoothstep(0.8, 1.2, d), step(0.0, dot(lightDirRing, ringPos))) + 0.02; // 朝光一侧更亮，加一点底亮。
        }
    }
    ring = mix(planetShadow * 0.49 + 0.01, ring, inRing); // 正对环面时用环带亮度，否则用行星阴影的固定暗带。
    transmittance = mix(0.7, transmittance, inRing); // 透过率同样按是否正对环面切换。
    color *= transmittance; // 环带吃掉一部分天光。
    ring *= 1.0 + mie * 10.0 * planetShadow; // 正对时叠一份米氏散射。
    color += ring * 0.012 * vec3(1.0, 0.85, 0.60); // 环带偏暖黄叠到画面。
}

// iterationT 末地天空的 p 曲线：四次方乘一次线性衰减，末端回到零。
float ogxEndSkyPCurve(float x)
{
    return ogxRadialCurve(x); // 环形径向轮廓只在数学模块维护一份。
}

#endif
