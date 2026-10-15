// 阴影深度绘制：把会挡光的几何体画进阴影贴图，只输出深度和透明裁切，不输出颜色。
// 管什么：阴影相机的顶点变换（与地形共用植物摆动）和片元的透明裁切，深度由加载器写进阴影纹理。
// 调用位置：三个维度目录的 shadow.vsh 与 shadow.fsh，各自定义 `OMNI_VERTEX` 或 `OMNI_FRAGMENT` 后引入本文件。
// 可复制示例：入口先写 #define OMNI_VERTEX，再引入本文件；阴影坐标与遮挡查询在 effects/shadow.glsl。
// 设计原因与取舍：这里只画深度不画颜色，颜色附件保留透明度给裁切使用；
// 半透明像素直接丢弃，换来叶片和草叶投出镂空阴影，代价是彩色玻璃不会投出带颜色的阴影。
// 阴影选项与阴影图坐标由共享效果文件提供，本文件只负责这一次绘制。
// 引入共享阴影定义。
#include "/effects/shadow.glsl"
// 引入植物摆动，阴影必须和主画面使用同一套位移，否则影子会和植物错开。
#include "/effects/vegetation.glsl"
#ifdef OMNI_VERTEX // 顶点阶段：准备裁切数据，并把顶点投到阴影相机。
in vec4 mc_Entity, mc_midTexCoord; // 方块类型与图块中点：分类决定能否摆动，中点判断顶点的上下半边。
out vec2 uv;   // 裁切纹理坐标：片元用它读取贴图并判断透明。
out vec4 tint; // 顶点颜色：片元用它乘贴图得到真实透明度。
// 取得阴影相机的世界位置，并让允许的植物摆动。
// 为什么先取反阴影相机矩阵：阴影绘制时加载器把模型视图矩阵换成了阴影相机，取反它就回到世界坐标。
// 为什么共用植物摆动：阴影若不动，植物会在地上留下静止的影子，和主画面的摆动对不上。
vec3 omniShadowWorld() {
    vec4 cameraRelative = gl_ModelViewMatrix * gl_Vertex;         // 顶点在阴影相机下的位置。
    vec3 world = (inverse(shadowModelView) * cameraRelative).xyz; // 还原成世界坐标，摆动和投影共用同一个位置。
    return omniVegetation(world, mc_Entity.x, uv.y < mc_midTexCoord.y ? 1.0 : 0.0); // 只偏移允许摆动的植物。
}
void main() {
    uv = gl_MultiTexCoord0.xy;      // 保留裁切坐标，后面判断植物和采样透明都用它。
    tint = gl_Color;                // 保留顶点颜色，透明度原样传给片元。
    vec3 world = omniShadowWorld(); // 顶点落到世界空间，并且已经跟随植物摆动。
    gl_Position = shadowProjection * shadowModelView * vec4(world, 1.0); // 用与阴影采样相同的投影写入深度。
}
#endif
#ifdef OMNI_FRAGMENT // 片元阶段：按透明度裁切，不透明的像素才遮挡光线。
uniform sampler2D gtexture; // 阴影阶段采样的方块贴图。
in vec2 uv;   // 顶点传来的裁切坐标。
in vec4 tint; // 顶点传来的颜色与透明度。
/* RENDERTARGETS: 0 */
layout(location=0) out vec4 color; // 阴影只写深度；颜色附件保留透明度，基础阴影不做彩色透射。
void main() {
    vec4 base = texture(gtexture, uv) * tint; // 贴图乘顶点色，得到本像素真实的底色与透明度。
    if (base.a < 0.5) discard; // 半透明以下的像素不写深度，否则草叶会投出整块实心影。
    color = base; // 深度由加载器写入阴影图，这里只保留透明度。
}
#endif
