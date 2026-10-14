// 反射：屏幕深度步进，未命中使用天空；示例 omniReflection(color, view, normal, materialParams, uv)。
#ifndef OMNI_REFLECTION
#define OMNI_REFLECTION
// @effect {"label":{"zh_cn":"反射","en_us":"Reflections"}}
// @option {"label":{"zh_cn":"屏幕空间反射","en_us":"Screen-space reflections"}}
//#define OMNI_SSR
// @option {"label":{"zh_cn":"反射步数","en_us":"Reflection steps"}}
#define OMNI_SSR_STEPS 24 // [12 24 48]
// @option {"label":{"zh_cn":"反射强度","en_us":"Reflection strength"},"slider":true}
#define OMNI_REFLECTION_STRENGTH 1.0 // [0.0 0.5 1.0]
// @option {"label":{"zh_cn":"反射去噪","en_us":"Reflection denoise"},"description":{"zh_cn":"按命中深度相似度加权多点，减少屏幕反射噪点。","en_us":"Weights multiple taps by hit depth similarity to reduce SSR noise."}}
#define OMNI_REFLECTION_DENOISE 1 // [0 1]
// 天空回退与屏幕重建共享输入。
#include "/effects/sky.glsl"
#include "/common/coordinates.glsl"
// 反射去噪：按命中深度相似度加权多个旋转采样，深度差大的邻点不参与。
vec3 omniReflectionFilter(vec2 hitUv, float hitDepth, float roughness) {
    float radius = mix(1.0,4.0,roughness); // 粗糙表面使用更大的过滤足迹。
    vec2 pixel = radius/vec2(viewWidth,viewHeight); // 采样步长折算到屏幕。
    vec3 sum = texture(colortex3,hitUv).rgb; float weight = 1.0; // 中心样本先参与平均。
    for (int i=0;i<8;i++) {
        float angle = float(i)*2.399963; // 旋转采样减少方向性条纹。
        vec2 sampleUv = clamp(hitUv+vec2(cos(angle),sin(angle))*pixel,0.0,1.0); // 屏幕内样本。
        float sampleDepth = texture(depthtex1,sampleUv).r; // 不透明深度。
        if (sampleDepth>=0.999999) continue; // 天空不参与去噪。
        vec3 sampleView = omniView(sampleUv,sampleDepth); // 邻点真实位置。
        float similarity = exp(-abs(sampleView.z-hitDepth)*2.0); // 深度相近才混合。
        sum += texture(colortex3,sampleUv).rgb*similarity; weight += similarity; // 加权累积。
    }
    return sum/max(weight,1e-4); // 按有效权重归一化。
}
vec3 omniReflected(vec3 view, vec3 normal, float roughness) {
    vec3 ray = reflect(omniNormalize(view),normal); // 视空间反射方向。
    vec3 reflected = omniSky(mat3(gbufferModelViewInverse)*ray); // 屏幕外或被遮挡时有明确环境回退。
#ifdef OMNI_SSR
    vec3 point = view + normal*0.15; // 起点离开表面避免自命中。
    for (int i=0;i<OMNI_SSR_STEPS;i++) {
        float stride = 0.25 + float(i)*0.15; // 远处增大步长。
        point += ray*stride; // 沿反射方向推进。
        if (point.z >= -near) break; // 相机背后没有屏幕样本。
        vec3 nearScreen = omniProject(point); // 近景射线使用普通投影与普通深度。
        bool hit = false; vec2 hitUv = nearScreen.xy; vec3 target = vec3(0.0); // 先保存统一的命中结果。
        if (all(greaterThanEqual(nearScreen.xy,vec2(0.01))) && all(lessThanEqual(nearScreen.xy,vec2(0.99)))) {
            float depth = texture(depthtex1,nearScreen.xy).r; // 近景深度只在自己的投影位置读取。
            if (depth < 0.999999) { target = omniView(nearScreen.xy,depth); hit = -point.z+target.z>0.0 && -point.z+target.z<stride*1.5; } // 近景命中。
        }
#ifdef DISTANT_HORIZONS
        if (!hit) {
            vec3 distantScreen = omniProjectDistant(point); // DH 射线改用远景投影。
            if (all(greaterThanEqual(distantScreen.xy,vec2(0.01))) && all(lessThanEqual(distantScreen.xy,vec2(0.99)))) {
                float depth = texture(dhDepthTex1,distantScreen.xy).r; // 远景深度与远景投影成对读取。
                if (depth < 0.999999 && texture(depthtex1,distantScreen.xy).r>=0.999999) { target = omniDistantView(distantScreen.xy,depth); hit = -point.z+target.z>0.0 && -point.z+target.z<stride*1.5; hitUv = distantScreen.xy; } // 远景颜色被近景遮住时不冒用近景颜色作为远景反射。
            }
        }
#endif
        if (hit && length(target-view)>0.2) {
#if OMNI_REFLECTION_DENOISE == 1
            vec3 sampleColor = omniReflectionFilter(hitUv,target.z,roughness); // 深度感知去噪。
#else
            vec2 blur = vec2(roughness*roughness*0.025); // 粗糙度控制反射足迹。
            vec3 sampleColor = texture(colortex3,hitUv).rgb * 0.4; // 命中颜色必须使用与命中深度相同的屏幕坐标。
            sampleColor += texture(colortex3,clamp(hitUv+vec2(blur.x,0),0.0,1.0)).rgb*0.15;
            sampleColor += texture(colortex3,clamp(hitUv-vec2(blur.x,0),0.0,1.0)).rgb*0.15;
            sampleColor += texture(colortex3,clamp(hitUv+vec2(0,blur.y),0.0,1.0)).rgb*0.15;
            sampleColor += texture(colortex3,clamp(hitUv-vec2(0,blur.y),0.0,1.0)).rgb*0.15;
#endif
            float edge = smoothstep(0.01,0.12,min(min(hitUv.x,hitUv.y),min(1.0-hitUv.x,1.0-hitUv.y))); // 边缘淡入回退。
            reflected = mix(reflected,sampleColor,edge); // 正确保留屏幕外天空。
            break; // 首个可用交点结束步进。
        }
    }
#endif
    return reflected; // 环境路径无需屏幕空间开关。
}
// 调用位置：rendering/composite.glsl；示例：omniReflection(color, view, normal, material.xyz, texcoord)。
vec3 omniReflection(vec3 color, vec3 view, vec3 normal, vec3 materialParams, vec2 uv) {
    if (OMNI_REFLECTION_STRENGTH<=0.0) return color; // 关闭反射后编译器移除天空和屏幕采样。
    float metal = step(230.0/255.0,materialParams.y); // 标准高区间是金属标志。
    vec3 f0 = mix(vec3(materialParams.y),clamp(color,0.0,1.0),metal); // 标准允许的底色金属近似。
    float facing = max(dot(normal,omniNormalize(-view)),0.0); // 掠射角提高反射。
    vec3 fresnel = f0 + (1.0-f0)*pow(1.0-facing,5.0); // 菲涅耳反射率。
    fresnel *= (1.0-materialParams.x*0.8)*OMNI_REFLECTION_STRENGTH; // 粗糙表面降低镜面峰值。
    return color*(1.0-fresnel) + omniReflected(view,normal,materialParams.x)*fresnel; // 能量在底色与反射间分配。
}
#endif
