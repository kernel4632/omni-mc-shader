// 阴影深度绘制：与地形共用植被运动；示例 shadow.vsh 引入。
// 阴影选项同时定义加载器距离与分辨率。
#include "/effects/shadow.glsl"
#include "/effects/vegetation.glsl"
#ifdef OMNI_VERTEX
in vec4 mc_Entity, mc_midTexCoord; // 方块类型与图块中点。
out vec2 uv; // 裁切纹理坐标。
out vec4 tint; // 透明度保留。
void main() {
    uv = gl_MultiTexCoord0.xy; tint = gl_Color; // 与主场景相同透明判定。
    vec4 position = gl_ModelViewMatrix*gl_Vertex; // 阴影相机位置。
    vec3 world = (inverse(shadowModelView)*position).xyz; // 还原相机相对世界位置。
    world = omniVegetation(world,mc_Entity.x,uv.y<mc_midTexCoord.y?1.0:0.0); // 阴影跟随植物运动。
    gl_Position = shadowProjection*shadowModelView*vec4(world,1.0); // 与阴影采样同一投影。
}
#endif
#ifdef OMNI_FRAGMENT
uniform sampler2D gtexture; // 阴影裁切纹理。
in vec2 uv; in vec4 tint; // 物体透明输入。
/* RENDERTARGETS: 0 */
layout(location=0) out vec4 color; // 阴影颜色附带保存透明度。
void main() {
    vec4 base = texture(gtexture,uv)*tint; // 实际透明像素不遮挡。
    if (base.a<0.5) discard; // 基础阴影不宣称彩色透明透射。
    color = base; // 深度由加载器写入阴影深度图。
}
#endif
