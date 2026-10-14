// 材质：解码实验室材质标准一点三；地形允许图集视差，实体和手只解码材质贴图。
#ifndef OMNI_MATERIAL
#define OMNI_MATERIAL
// @effect {"label":{"zh_cn":"材质","en_us":"Materials"}}
// @option {"label":{"zh_cn":"实验室材质标准","en_us":"labPBR 1.3"},"description":{"zh_cn":"需要实验室材质标准一点三资源包；关闭时使用普通贴图。预定义金属按标准允许的底色近似。","en_us":"Requires labPBR 1.3 maps; predefined metals use the permitted albedo approximation."}}
//#define OMNI_LABPBR
// @option {"label":{"zh_cn":"视差深度","en_us":"Parallax depth"},"slider":true}
#define OMNI_PARALLAX 0.0 // [0.0 0.02 0.05 0.1]
// @option {"label":{"zh_cn":"湿润表面","en_us":"Wet surfaces"}}
#define OMNI_WET_SURFACES
// @option {"label":{"zh_cn":"积雪覆盖","en_us":"Snow coverage"},"description":{"zh_cn":"手动外观选项，按天空光与表面朝上程度覆盖；不推断生物群系温度。","en_us":"Artistic coverage based on skylight and surface orientation, not biome temperature."}}
#define OMNI_SNOW 0.0 // [0.0 0.25 0.5 1.0]
// 贴图编码和天气输入共用。
#include "/common/math.glsl"
#include "/common/uniforms.glsl"
#ifdef OMNI_LABPBR
uniform sampler2D normals, specular; // 加载器提供资源包法线与表面纹理。
#endif
// 调用位置：rendering/terrain.glsl的片元步骤；示例：omniMaterial(base, normal, props, materialAo, uv, bounds, tbn, view, allowParallax)。
void omniMaterial(inout vec4 base, inout vec3 normal, inout vec3 props, out float materialAo, inout vec2 uv, vec4 bounds, mat3 tbn, vec3 view, bool allowParallax) {
    materialAo = 1.0; // 普通贴图和缺失PBR资源使用不遮蔽的线性默认值。
#ifdef OMNI_LABPBR
    vec2 dx = dFdx(uv), dy = dFdy(uv); // 视差循环不使用不稳定的隐式导数。
    if (allowParallax && OMNI_PARALLAX > 0.0) { // 实体与手只解码材质，避免把非图集边界当作视差边界。
        vec3 tangentView = transpose(tbn) * omniNormalize(-view); // 观察方向转贴图空间。
        vec2 stepUv = tangentView.xy / max(abs(tangentView.z),0.15) * OMNI_PARALLAX * (bounds.zw-bounds.xy) / 16.0; // 深度随图块大小缩放。
        float layer = 0.0; // 从表面向内部寻找高度交点。
        for (int i=0;i<16;i++) {
            float height = textureGrad(normals,uv,dx,dy).a; // 高度来自法线贴图透明通道。
            if (layer >= 1.0-height) break; // 遇到真实高度就停止。
            uv = clamp(uv-stepUv,bounds.xy,bounds.zw); // 不跨出图集图块。
            layer += 1.0/16.0; // 固定层数控制开销。
        }
        base = textureGrad(gtexture,uv,dx,dy) * base; // 调用者传入顶点色，视差后重新采样底色。
    } else { // 关闭视差仍读取材质法线。
        base *= texture(gtexture,uv); // 普通法线路径保留原始图块。
    }
    vec4 n = textureGrad(normals,uv,dx,dy); // 标准法线与遮蔽、高度数据。
    vec2 xy = vec2(n.r*2.0-1.0,1.0-n.g*2.0); // 标准使用向下的绿色轴。
    normal = omniNormalize(tbn * vec3(xy,sqrt(max(1.0-dot(xy,xy),0.0)))); // 重建第三轴。
    vec4 s = textureGrad(specular,uv,dx,dy); // 表面数据使用线性值。
    props = vec3(max(pow(1.0-s.r,2.0),0.025),s.g,s.a < 0.999 ? s.a*255.0/254.0 : 0.0); // 忽略缺省透明通道的自发光。
    materialAo = n.b; // 材质遮蔽独立保存，后续只进入环境光。
#else
    base *= texture(gtexture,uv); // 无材质资源包时不采样未提供的材质纹理。
#endif
}
void omniSurface(inout vec3 color, inout vec3 props, vec3 normal, vec3 world, float skylight) {
    float up = max((mat3(gbufferModelViewInverse)*normal).y,0.0); // 朝上表面接收雨雪。
#ifdef OMNI_WET_SURFACES
    float wet = wetness * up * smoothstep(0.7,1.0,skylight); // 洞穴与垂直墙面不凭空湿润。
    color *= 1.0-wet*0.25; // 湿润表面变暗。
    props.x = mix(props.x,0.08,wet); // 积水提高光滑程度。
#endif
    if (OMNI_SNOW>0.0) { // 零覆盖常量移除空间噪声计算。
        float snow = OMNI_SNOW * up * smoothstep(0.7,1.0,skylight) * smoothstep(0.3,0.7,omniNoise((world+cameraPosition)*0.2)); // 空间纹理控制雪边缘。
        color = mix(color,vec3(0.85,0.9,0.96),snow); // 手动雪覆盖使用线性底色。
        props.x = mix(props.x,0.85,snow); // 雪为粗糙非金属表面。
        props.y = mix(props.y,0.04,snow); // 积雪降低金属反射。
    }
}
#endif
