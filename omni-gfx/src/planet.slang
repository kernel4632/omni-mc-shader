/*
Omni 通用图形库行星模块：用解析射线画出整颗行星、光环与大气，不依赖任何宿主状态。
调用位置：末地天空与末地反射；Minecraft 光影由 `/omni-gfx/planet.glsl` 引入，
    `rendering/world/planet.glsl` 只保留时间与阴影强度的换算。
可复制示例：`ogxPlanetEnd(color, eye, rayDir, lightDir, shadowVector, time, planetShadow, noiseTex);`
设计原因与取舍：行星半径、相机高度、时间、阴影强度与噪声贴图全部由调用方传入，库只做纯计算；
    星场与吸积盘不在这里，行星本体只负责地表、环带与大气这三段。
    旋转矩阵沿用原程序的扁平构造参数顺序，生成 GLSL 后由 GLSL 的列主序规则解释，
    与旧实现逐位一致；不要在 Slang 侧改成按列传入。
*/
#ifndef OGX_PLANET_INCLUDED
#define OGX_PLANET_INCLUDED

// 数学提供求交、圆盘剖面与色温，大气提供米氏相位与行星双向反射。
#include "common/math.slang"
// 大气提供散射、密度剖面与天球映射。
#include "atmosphere/atmosphere.slang"

// 画一整颗行星：先与地表球求交，再叠光环与大气，最后把环带的遮挡乘回天空。
// `eye` 是相机在行星坐标系里的位置，`rayDir` 是视线，`lightDir` 是光方向。
// `shadowVector` 只用于米氏相位的观察方向，`time` 驱动行星与光环的缓慢摆动。
// `planetShadow` 是行星落在天空上的阴影强度，`noiseTex` 提供环带细缝的五层噪声。
void ogxPlanetEnd(inout float3 color, float3 eye, float3 rayDir, float3 lightDir,
    float3 shadowVector, float time, float planetShadow, Sampler2D noiseTex)
{
    const float Rground = 20e6; // 行星半径。
    const float Ratmo = 20.1e6; // 大气层顶半径。
    eye.y += Rground; // 相机抬到行星表面之上。
    eye.y += 15e6; // 再抬高，模拟远离行星的视角。
    float VdotL = dot(shadowVector, rayDir); // 视线与阳光夹角余弦，供相位使用。
    float mie = ogxMiePhase(0.8, VdotL); // 米氏相位。
    float angleX = -1.57079633 + (0.2 * sin(time + 3.0) - 0.1); // 俯仰角随时间摆动。
    float angleY = time; // 偏航角随时间转动。
    float3x3 eyeRoataionMatrixX = float3x3(1.0, 0.0, 0.0, 0.0, cos(angleX), -sin(angleX), 0.0, sin(angleX), cos(angleX)); // 俯仰旋转矩阵。
    float3x3 eyeRoataionMatrixY = float3x3(cos(angleY), 0.0, sin(angleY), 0.0, 1.0, 0.0, -sin(angleY), 0.0, cos(angleY)); // 偏航旋转矩阵。
    float3x3 eyeRoataionMatrix = eyeRoataionMatrixX * eyeRoataionMatrixY; // 合成旋转。
    float ringAngle = 0.008 * sin(time + 4.6); // 光环的倾角随时间轻微摆动。
    float3x3 ringRoataionMatrix = float3x3(1.0, 0.0, 0.0,
                                           0.0, cos(ringAngle), sin(ringAngle),
                                           0.0, -sin(ringAngle), cos(ringAngle)); // 光环旋转矩阵。
    float3x3 ringRoataionMatrixInverse = transpose(ringRoataionMatrix); // 光环旋转的逆。
    rayDir = ogxMatrix3MulPoint(eyeRoataionMatrix, rayDir); // 视线转到行星坐标系。
    lightDir = ogxMatrix3MulPoint(eyeRoataionMatrix, lightDir); // 光方向同样转过去。
    float3 rayDirRing = ogxMatrix3MulPoint(ringRoataionMatrix, rayDir); // 视线转到光环坐标系。
    float3 lightDirRing = ogxMatrix3MulPoint(ringRoataionMatrix, lightDir); // 光方向转到光环坐标系。
    float3 ringOrigin = float3(0.0, cos(ringAngle), sin(ringAngle)) * (eye.y / Rground); // 光环所在平面的原点。
    float2 ringRadius = float2(1.6, 2.6); // 光环内外半径。
    float3 surface = float3(0.0); // 行星表面与光环累积的颜色。
    float LdotR = dot(rayDir, -lightDir); // 光线与视线夹角余弦。
    float2 groundIntersection = ogxRaySphereIntersection(eye, rayDir, Rground); // 与行星地表求交。
    float2 topAtmoIntersection = ogxRaySphereIntersection(eye, rayDir, Ratmo); // 与大气层顶求交。
    float3 surfacePos = rayDir * groundIntersection.x; // 地表交点位置。
    float3 surfaceNormal = normalize(surfacePos + float3(0.0, eye.y, 0.0)); // 地表法线，由球心指向交点。
    if (groundIntersection.y > 0.0) // 射线打到行星本体。
    {
        color *= 0.0; // 本体完全遮住后面的天光。
        float3 surfaceAlbedo = float3(0.98, 0.87, 0.55); // 行星表面底色，偏暖白。
        surface = ogxPlanetBrdf(surfaceAlbedo, surfaceNormal, -rayDir, lightDir); // 算地表着色。
        float3 origin = ringOrigin + surfacePos / Rground; // 光环采样的起点。
        float3 rayPos = ogxRayPlaneIntersection(origin, lightDirRing, float3(0.0, 0.0, 1.0)); // 沿光方向与光环平面求交。
        float rayRadius = length(rayPos); // 交点到光环中心的半径。
        if (rayRadius > ringRadius.x && rayRadius < ringRadius.y && dot(rayPos - origin, lightDirRing) > 0.0) // 落在环带内且朝光一侧。
        {
            float ringNoise = ogxPlanetRingNoise(rayRadius * 0.5 + 0.69, noiseTex); // 五层噪声叠出环带细缝。
            surface *= exp(-pow(ogxSaturate(ringNoise) * 1.5, 3.0) * smoothstep(ringRadius.x, ringRadius.x * 1.1, rayRadius)); // 噪声把环带压出缝隙。
        }
        float UdotN = ogxSaturate(dot(ringRoataionMatrixInverse[2], surfaceNormal)); // 光环上表面法线与地表法线夹角。
        float DdotN = ogxSaturate(dot(-ringRoataionMatrixInverse[2], surfaceNormal)); // 光环下表面同理。
        float OLdotN = ogxSaturate(dot(ogxMatrix3MulPoint(ringRoataionMatrixInverse, normalize(float3(-lightDir.xy, 0.0))), surfaceNormal)); // 光线在环面上的投影与法线夹角。
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
        topAtmoMie *= lerp(1.0, smoothstep(0.9, 0.4, dot(surfaceNormal, normalize(eye))), isGround); // 打到地面时按视线角度衰减。
        surface += topAtmoMie * float3(0.65, 0.7, 1.0); // 大气偏冷蓝。
    }
    color += surface * 0.6; // 地表与大气叠加到画面。
    float inRing = ogxSaturate(abs(ringAngle) * 3000.0 - 0.8); // 当前是否正对环面。
    float ring = 0.0; // 环带的亮度。
    float transmittance = 1.0; // 环带留下的透过率。
    if (rayDirRing.z * ringAngle < 0.0) // 视线穿过环面。
    {
        float3 origin = float3(0.0, cos(ringAngle), sin(ringAngle)) * (eye.y / Rground); // 环面原点。
        float3 ringPos = ogxRayPlaneIntersection(origin, rayDirRing, float3(0.0, 0.0, 1.0)); // 视线与环面求交。
        float rayRadius = length(ringPos); // 交点到环心半径。
        float2 ringRadius2 = float2(1.6, 2.6); // 环带内外半径。
        if (rayRadius > ringRadius2.x && rayRadius < ringRadius2.y) // 落在环带内。
        {
            float ringNoise = ogxPlanetRingNoise(rayRadius * 0.5 + 0.69, noiseTex); // 五层噪声叠出环带细缝。
            ring += pow(ogxSaturate(ringNoise) * 1.5, 3.0); // 噪声得到环带形状。
            ring *= smoothstep(ringRadius2.x, ringRadius2.x * 1.1, rayRadius); // 内边缘渐入。
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
    ring = lerp(planetShadow * 0.49 + 0.01, ring, inRing); // 正对环面时用环带亮度，否则用行星阴影的固定暗带。
    transmittance = lerp(0.7, transmittance, inRing); // 透过率同样按是否正对环面切换。
    color *= transmittance; // 环带吃掉一部分天光。
    ring *= 1.0 + mie * 10.0 * planetShadow; // 正对时叠一份米氏散射。
    color += ring * 0.012 * float3(1.0, 0.85, 0.60); // 环带偏暖黄叠到画面。
}

// iterationT 末地天空的 p 曲线：四次方乘一次线性衰减，末端回到零。
float ogxEndSkyPCurve(float x)
{
    return ogxRadialCurve(x); // 环形径向轮廓只在数学模块维护一份。
}

#endif
