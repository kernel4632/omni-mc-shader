// 反射：屏幕空间反射沿深度步进找不透明几何，未命中回退到天空环境，屏幕空间反射默认关闭。
// 调用位置：rendering/composite.glsl 的普通与湿润表面，以及 effects/water.glsl 的水面反射。
// 可复制示例：`vec3 lit = omniReflection(color, view, normal, materialParams, uv);`
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
// 近景命中：把视空间点投到近景屏幕并读取普通深度，命中时给出屏幕坐标与真实交点。
bool omniNearHit(vec3 point, float stride, out vec2 hitUv, out vec3 target) {
    vec3 screen = omniProject(point); // 近景射线使用普通投影。
    hitUv = screen.xy; target = vec3(0.0); // 默认交点为空，屏幕坐标先记录。
    if (any(lessThan(screen.xy,vec2(0.01))) || any(greaterThan(screen.xy,vec2(0.99)))) return false; // 屏幕外不接受命中。
    float depth = texture(depthtex1,screen.xy).r; // 近景深度只在自己的投影位置读取。
    if (depth>=0.999999) return false; // 天空不是几何命中。
    target = omniView(screen.xy,depth); // 命中处的视空间位置。
    float travel = -point.z+target.z; // 射线相对命中表面的深度差。
    return travel>0.0 && travel<stride*1.5; // 深度差在一步内才算命中。
}
// 远景命中：射线改用远景投影与远景深度，近景已有几何时不冒用为远景反射。
bool omniDistantHit(vec3 point, float stride, out vec2 hitUv, out vec3 target) {
#ifdef DISTANT_HORIZONS
    vec3 screen = omniProjectDistant(point); // 远景射线必须使用远景自己的投影。
    hitUv = screen.xy; target = vec3(0.0); // 默认交点为空，屏幕坐标先记录。
    if (any(lessThan(screen.xy,vec2(0.01))) || any(greaterThan(screen.xy,vec2(0.99)))) return false; // 屏幕外不接受命中。
    if (texture(depthtex1,screen.xy).r<0.999999) return false; // 近景已有几何时远景不冒用反射。
    float depth = texture(dhDepthTex1,screen.xy).r; // 远景深度与远景投影成对读取。
    if (depth>=0.999999) return false; // 远景天空不是几何命中。
    target = omniDistantView(screen.xy,depth); // 用远景逆投影还原真实位置。
    float travel = -point.z+target.z; // 射线相对命中表面的深度差。
    return travel>0.0 && travel<stride*1.5; // 深度差在一步内才算命中。
#else
    hitUv = vec2(0.0); target = vec3(0.0); // 没有远景时明确不使用命中结果。
    return false; // 基础路径没有远景命中。
#endif
}
// 逐像素反射：先取天空环境回退，再沿反射方向步进，命中几何时混入屏幕颜色。
vec3 omniReflected(vec3 view, vec3 normal, float roughness) {
    vec3 ray = reflect(omniNormalize(view),normal); // 视空间反射方向。
    vec3 reflected = omniSky(mat3(gbufferModelViewInverse)*ray); // 屏幕外或被遮挡时回退到天空。
#ifdef OMNI_SSR
    vec3 point = view + normal*0.15; // 起点离开表面避免自命中。
    for (int i=0;i<OMNI_SSR_STEPS;i++) {
        float stride = 0.25 + float(i)*0.15; // 远处增大步长。
        point += ray*stride; // 沿反射方向推进。
        if (point.z >= -near) break; // 相机背后没有屏幕样本。
        vec2 hitUv; vec3 target; // 下面两个检测按顺序写入命中坐标与交点。
        bool hit = omniNearHit(point,stride,hitUv,target); // 先试近景屏幕深度。
        if (!hit) hit = omniDistantHit(point,stride,hitUv,target); // 近景未中再试远景。
        if (!hit || length(target-view)<=0.2) continue; // 太近的交点是自身，忽略后继续步进。
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
