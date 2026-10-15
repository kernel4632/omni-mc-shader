// 材质：把资源包的底色、法线、表面三张贴图解码成光照用的表面数据，再叠加湿润与积雪。
// 职责：不透明表面解码（实验室材质标准一点三：法线、高度、遮蔽、平滑度、金属、自发光）与气候天气叠加，地形和实体共用。
// 调用位置：rendering/terrain.glsl 的片元步骤；omniReadSurface 调 omniMaterial 解码，omniShadeSurface 调 omniSurface 加天气。
// 可复制示例：omniMaterial(base,normal,materialParams,materialAo,uv,bounds,tangentFrame,view,true); omniSurface(albedo,materialParams,normal,world,skylight);
// 设计取舍一：加载器没给材质贴图、切线退化或通道越界时一律回退到不含材质的稳定结果，任何资源包缺失都不影响基础画面。
// 设计取舍二：视差只在图块边界已知的地形上开启；实体和手没有可靠图集，强行偏移会采到相邻方块，所以只解码不偏移。
#ifndef OMNI_MATERIAL
#define OMNI_MATERIAL
// @effect {"label":{"zh_cn":"材质","en_us":"Materials"}}
// @option {"label":{"zh_cn":"材质细节开关","en_us":"labPBR 1.3"},"description":{"zh_cn":"需要实验室材质标准一点三资源包；关闭时使用普通贴图。预定义金属按标准允许的底色近似。","en_us":"Requires labPBR 1.3 maps; predefined metals use the permitted albedo approximation."}}
//#define OMNI_LABPBR
// @option {"label":{"zh_cn":"凹凸深度","en_us":"Parallax depth"},"slider":true}
#define OMNI_PARALLAX 0.0 // [0.0 0.02 0.05 0.1]
// @option {"label":{"zh_cn":"湿润开关","en_us":"Wet surfaces"}}
#define OMNI_WET_SURFACES
// @option {"label":{"zh_cn":"湿润程度","en_us":"Wetness strength"},"slider":true}
#define OMNI_WET_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"积雪程度","en_us":"Snow strength"},"slider":true}
#define OMNI_SNOW_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"额外积雪","en_us":"Snow coverage"},"description":{"zh_cn":"手动额外覆盖，按天空光与表面朝上程度叠加；不推断生物群系温度。","en_us":"Extra artistic coverage based on skylight and surface orientation, not biome temperature."}}
#define OMNI_SNOW 0.0 // [0.0 0.25 0.5 1.0]
// @option {"label":{"zh_cn":"自动积雪开关","en_us":"Climate snow/wet"},"description":{"zh_cn":"按高度与空间噪声估计温度，冷处自然积雪、温暖处更易积水；不读取真实生物群系数据。","en_us":"Estimates temperature from altitude and spatial noise for natural snow and wetness, without biome data."}}
#define OMNI_CLIMATE 1 // [0 1]
// 贴图解码和天气叠加共享归一化、噪声等通用计算与相机、湿度等统一输入变量。
#include "/common/math.glsl"
#include "/common/uniforms.glsl"
#ifdef OMNI_LABPBR
uniform sampler2D normals, specular; // 加载器按资源包提供法线与表面两张贴图。
// 视差步进：沿视线在高度图里向前找可见交点，返回被近处凸起遮住的贴图坐标。
// 为什么固定十六步：步数直接决定开销和精度，写死才能让编译器和玩家都预知代价，避免可变长循环。
// 为什么每步都钳制在 `bounds` 内：图集里相邻方块共用一张大图，越界会采到隔壁方块的高度，位移就会跳到别的贴图。
vec2 omniParallaxUv(vec2 uv, vec2 stepUv, vec4 bounds, vec2 dx, vec2 dy) {
    float depth = 0.0; // 已向表面内部推进的深度，零表示还停在表面。
    for (int i=0;i<16;i++) {
        float height = textureGrad(normals,uv,dx,dy).a; // 高度存在法线贴图的透明通道，值越大表示这一点越靠近观察者。
        if (depth >= 1.0-height) break; // 推进深度追上了这一点的真实高度，说明交点就在脚下，提前结束。
        uv = clamp(uv-stepUv,bounds.xy,bounds.zw); // 每次只走一小步，并始终留在本图块内。
        depth += 1.0/16.0; // 十六步正好走满一个深度周期。
    }
    return uv; // 返回被遮挡后的真实采样坐标。
}
// 法线解码：把一个实验室材质法线纹素还原成视空间单位法线，数据坏了就回退几何法线。
// 通道含义：R、G 是切线平面的两个轴；标准规定绿色轴朝下，和纹理坐标的朝上相反，所以 G 要翻转。
// 为什么检查平方长度：资源包可能缺通道或写出越界值，补回的第三轴会变成零向量或非数，必须先判掉。
vec3 omniDecodeNormal(vec4 texel, mat3 tangentFrame, vec3 geometry) {
    vec2 xy = vec2(texel.r*2.0-1.0,1.0-texel.g*2.0); // 从零到一还原成负一到一，同时把绿色轴翻成朝上。
    float plane = dot(xy,xy); // 切线平面上的平方长度，用来推断这个法线还剩多少平面分量。
    vec3 mapped = tangentFrame * vec3(xy,sqrt(max(1.0-plane,0.0))); // 用第三轴补回单位长度，再转到视空间。
    bool usable = plane <= 1.0 && dot(mapped,mapped) > 1e-6; // 平面分量越界或切线基退化都判为不可用。
    return usable ? omniNormalize(mapped) : geometry; // 可用就用解码结果，否则退回几何法线，画面不至于翻转。
}
#endif
// 材质解码：读取并解开实验室材质贴图，写回底色、视空间法线、粗糙金属自发光与遮蔽。
// 参数里的 `bounds` 是图块在整张图集里的边界，`tangentFrame` 是切线基，`allowParallax` 表示调用者是否允许视差。
void omniMaterial(inout vec4 base, inout vec3 normal, inout vec3 materialParams, out float materialAo, inout vec2 uv, vec4 bounds, mat3 tangentFrame, vec3 view, bool allowParallax) {
    materialAo = 1.0; // 普通贴图或缺失材质时使用不遮蔽的默认值，后续只让环境光读取它。
#ifdef OMNI_LABPBR
    vec3 geometry = normal; // 先记住几何法线，法线贴图缺失或损坏时回退到它。
    vec2 dx = dFdx(uv), dy = dFdy(uv); // 显式导数：视差循环里坐标会变，循环中不能用隐式导数。
    bool atlasValid = bounds.z > bounds.x && bounds.w > bounds.y; // 只有图块边界有效时才允许视差。
    if (allowParallax && OMNI_PARALLAX > 0.0 && atlasValid) { // 实体和手图集边界不可靠，只解码不偏移。
        vec3 tangentView = transpose(tangentFrame) * omniNormalize(-view); // 观察方向从视空间转到贴图切线空间。
        vec2 stepUv = tangentView.xy / max(abs(tangentView.z),0.15) * OMNI_PARALLAX * (bounds.zw-bounds.xy) / 16.0; // 每步坐标增量：视线越斜步越大，并随图块尺寸缩放以保持深度手感一致。
        uv = omniParallaxUv(uv,stepUv,bounds,dx,dy); // 偏移后的坐标才是真正要采样的位置。
        base = textureGrad(gtexture,uv,dx,dy) * base; // 调用者传入的是顶点色，视差后要重新乘上被遮挡处底贴图。
    } else { // 关闭视差或图块无效时，普通采样保留原始坐标。
        base *= texture(gtexture,uv); // 这里坐标不变，隐式导数够用，也省一次显式梯度。
    }
    vec4 n = textureGrad(normals,uv,dx,dy); // 法线贴图：R、G 是切线法线，B 是遮蔽，A 是视差高度。
    normal = omniDecodeNormal(n,tangentFrame,geometry); // 解码成视空间单位法线，无效时回退几何法线。
    vec4 s = textureGrad(specular,uv,dx,dy); // 表面贴图：R 是平滑度，G 是金属度，A 是自发光。
    float smoothness = clamp(s.r,0.0,1.0); // 图集边缘采样可能越界，先夹到合法范围，避免后面的幂运算出非数。
    float metalness = clamp(s.g,0.0,1.0); // 金属标志同样夹到零到一，越界值当边界处理。
    float emissive = s.a < 0.999 ? s.a*255.0/254.0 : 0.0; // 资源包不给自发光时会把透明通道写满，写满视为零发光，其余线性放大到零到一。
    materialParams = vec3(max(pow(1.0-smoothness,2.0),0.025),metalness,emissive); // 平滑度取平方换成粗糙度，并留最小下限，避免镜面反射除零。
    materialAo = n.b; // 遮蔽单独保存，只进环境光，不影响直接光。
#else
    base *= texture(gtexture,uv); // 没有材质资源包时只采底贴图，不采样未提供的法线和表面纹理。
#endif
}
// 气候温度：从绝对高度和一片空间噪声估计零到一的温度，零为寒冷，一为炎热。
float omniTemperature(vec3 world) {
    vec3 p = world+cameraPosition; // 传进来的是相机相对坐标，加上相机位置才能得到稳定的绝对坐标。
    float base = 0.5+(omniNoise(p*0.01)-0.5)*0.8; // 大尺度噪声形成温度带，振幅零点八让它不整体偏向一侧。
    float altitude = (p.y-64.0)/128.0; // 以海平面六十四格为基准，每升高一百二十八格算一份降温。
    return clamp(base-altitude*0.8,0.0,1.0); // 高度降温占八成权重，结果夹在零到一。
}
// 气候天气：在解码好的表面上叠加湿润和积雪，只改底色明暗与粗糙、金属参数。
void omniSurface(inout vec3 color, inout vec3 materialParams, vec3 normal, vec3 world, float skylight) {
    float up = max((mat3(gbufferModelViewInverse)*normal).y,0.0); // 法线转到世界空间：只有朝上的面才接得住雨雪。
    float snow = OMNI_SNOW*OMNI_SNOW_STRENGTH; // 手动覆盖量乘强度作为下限，气候只会在它之上追加积雪。
    float wetnessAmount = wetness; // 加载器湿润度作为默认，气候会再乘一个温度权重。
#if OMNI_CLIMATE == 1
    float temperature = omniTemperature(world); // 估计这一处的气候温度。
    snow = max(snow,1.0-smoothstep(0.10,0.30,temperature)); // 正序计算后取反：温度不高于零点一时全雪，不低于零点三时没有气候雪。
    wetnessAmount = wetness*(0.5+0.5*temperature); // 按菜单意图让暖处更湿，最冷处保留一半基础湿润。
#endif
#ifdef OMNI_WET_SURFACES
    float wet = clamp(wetnessAmount * up * smoothstep(0.7,1.0,skylight) * OMNI_WET_STRENGTH,0.0,1.0); // 洞穴和垂直墙面没有天光，不凭空变湿；强度选项整体放大或缩小。
    color *= 1.0-wet*0.25; // 湿表面反光偏暗，最多压暗四分之一。
    materialParams.x = mix(materialParams.x,0.08,wet); // 积水处更光滑，把粗糙度往零点零八靠。
#endif
    if (snow>0.0) { // 覆盖量为零时整段跳过，省下一次空间噪声采样。
        float cover = snow * up * smoothstep(0.7,1.0,skylight) * smoothstep(0.3,0.7,omniNoise((world+cameraPosition)*0.2)); // 用噪声把雪边打碎，避免整齐的色块。
        color = mix(color,vec3(0.85,0.9,0.96),cover); // 雪用偏蓝的线性白色叠在底色上。
        materialParams.x = mix(materialParams.x,0.85,cover); // 雪很粗糙。
        materialParams.y = mix(materialParams.y,0.04,cover); // 雪几乎不反光，金属度压到接近零。
    }
}
#endif
