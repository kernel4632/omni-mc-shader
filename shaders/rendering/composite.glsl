/*
场景合成：屏幕空间后处理的汇总文件，按固定顺序把水、反射、环境遮蔽、云、雾和闪电叠回已经着色的画面。

在什么位置被调用：
  各维度的 composite.fsh 定义 OMNI_FRAGMENT 后引入本文件，由加载器的合成程序在全屏三角形上执行；
  同一份代码用 OMNI_VERTEX 提供全屏顶点着色器，两个阶段共用 texcoord。

可复制示例（只演示调用顺序，真正由 main 驱动）：
  `vec3 color = texture(colortex0, texcoord).rgb;`   拿到前向照明与原版透明混合的结果
  `color = omniCompositeSurface(color, texcoord);`   依次叠水、反射、遮蔽、云、雾、闪电
  `colorOut = vec4(color, 1.0);`                      交给时间抗锯齿阶段

设计原因与取舍：
  所有效果都读同一份缓冲、只改颜色，所以先后顺序是硬约束，不能随意调换。
  顺序是：先水面（定下折射与反射），再环境遮蔽与反射（贴在表面上），
  然后云与雾（挡在几何前方），闪电放最后（它是按位置的照明，不该再被云雾遮一次）。
  中间画面的编号与用途只在 rendering/buffers.glsl 约定一处，本文件按编号取用，不重复定义。
  合成阶段不重算光照，只对已经着色的颜色做屏幕后处理；真正的照明在几何与光照阶段完成。
*/

// --- 全屏顶点：铺满屏幕并把屏幕位置交给片元阶段 ---
#ifdef OMNI_VERTEX
out vec2 texcoord; // 全屏纹理坐标，水平与垂直都在零到一之间。
void main() {
    gl_Position = ftransform(); // 使用原版给定的顶点位置，不做任何额外变换。
    texcoord = gl_MultiTexCoord0.xy; // 顶点自带的多重纹理坐标就是屏幕位置。
}
#endif

#ifdef OMNI_FRAGMENT
// --- 引入：缓冲协议与全部要叠加的效果，生效时各自按需读取屏幕 ---
// 缓冲协议：中间画面的编号、通道与用途只在这里声明一次，其他文件按它取用。
#include "/rendering/buffers.glsl"
// 时序噪声：给环境遮蔽等采样一个逐帧旋转的相位，配合时间重建去除噪点。
#include "/effects/antialiasing.glsl"
// 环境遮蔽与屏幕空间反弹光：用屏幕里看得见的邻点压暗被遮挡的部分。
#include "/effects/ambient.glsl"
// 水面：折射、分波段吸收与水面反射，读取水面自身的深度。
#include "/effects/water.glsl"
// 云：在几何之前画出云层，让云挡住地形之后的天空。
#include "/effects/cloud.glsl"
// 雾：按距离与维度给景物加入空气感，透明表面用最近可见深度。
#include "/effects/fog.glsl"
// 氛围：极光、彩虹、大气散射，以及按位置叠加的闪电照明。
#include "/effects/atmosphere.glsl"
// 天气：雨天整体压暗。
#include "/effects/weather.glsl"
in vec2 texcoord; // 全屏采样位置，由顶点阶段插值得到。
/* RENDERTARGETS: 6 */
layout(location=0) out vec4 colorOut; // 时间抗锯齿之前的线性颜色。

// --- 水与反射：水面读自身深度做折射，其他表面做环境遮蔽与反射 ---
// 输入来自哪里：颜色来自不透明与透明几何混合后的前向照明；水附件在透明阶段写入，
//   深度为负表示这一像素有水，此时顶部已给出水面法线；类别等于二表示手持物。
// 为什么先做这一步：水面会换掉颜色的来源，后面的遮蔽与反射必须叠在水面颜色之上。
// 手持物为什么不参与：手持物离相机极近，屏幕里找不到可信的邻点，做世界遮蔽与反射会抖动。
vec3 omniSurfaceWater(vec3 color, vec3 view, vec3 normal, float category, vec4 water, vec3 material, vec2 uv) {
    if (water.a<0.0) return omniWater(view,normal,uv); // 有水就直接做折射与分波段吸收，不再叠屏幕遮蔽。
    if (category!=2.0) { // 不是手持物，才用屏幕里的邻点做遮蔽与反射。
        color = omniAmbient(color,view,normal,uv); // 用邻点几何压暗被挡住的部分。
        color = omniReflection(color,view,normal,material,uv); // 叠加屏幕里照到的反射与天空回退。
    }
    return color; // 返回叠完水面与表面效果的颜色。
}

// --- 云与雾：只对看得到几何或独立水面的像素，在它前方叠加云与雾 ---
// 输入来自哪里：世界方向由视空间位置换算得到，云按方向铺在天球上；
//   视线长度当作云的距离，越远云越厚；雾用最近的可见深度决定浓度。
// 为什么放在表面效果之后：云和雾是挡在物体前方的，必须先知道前方有多远，才能决定挡多少。
vec3 omniSurfaceAir(vec3 color, vec3 view, vec3 world, float category, float waterDepth, vec2 uv) {
    if (category==2.0 && waterDepth>=0.0) return color; // 手持物且没有独立水面，前方没有云雾可挡，直接返回。
    color = omniCloud(color,omniNormalize(world),length(view)); // 用视线长度当云的距离，越远云越厚。
    color = omniFog(color,view,world); // 用最近可见深度给透明表面加雾。
    return color; // 返回叠完云与雾的颜色。
}

// --- 单像素几何后处理：一次读完元数据，依次叠水、反射、云、雾与闪电 ---
// 输入来自哪里：颜色是前向照明结果；缓冲一给法线与类别，缓冲二给材质，
//   缓冲八给水法线与水面深度，缓冲七的有效标志表示这个像素是否真的有几何。
// 为什么集中读一次：四份元数据对应同一个屏幕像素，一次取齐，后面各步骤共用同一批数值。
vec3 omniCompositeSurface(vec3 color, vec2 uv) {
    ivec2 pixel = omniPixel(uv); // 连续坐标转整数像素，按统一坐标模块夹到屏幕范围内。
    if (texelFetch(colortex7,pixel,0).a<0.5) return color; // 没有几何也没有覆盖层，这个像素不需要几何后处理。
    vec3 view = omniSceneView(uv,false); // 从深度还原视空间位置，近景与远景统一。
    vec3 world = omniWorld(view); // 换算成相机相对的世界位置，供云、雾与闪电使用。
    vec4 geometry = texelFetch(colortex1,pixel,0); // 缓冲一：法线编码与表面类别，精确配对不做插值。
    vec4 material = texelFetch(colortex2,pixel,0); // 缓冲二：粗糙度、金属、自发光与天空光。
    vec4 water = texelFetch(colortex8,pixel,0); // 缓冲八：水的独立法线与视空间深度。
    vec3 normal = omniNormalize((water.a<0.0?water.xyz:geometry.xyz)*2.0-1.0); // 有水时用水面法线，否则用几何法线。
    color = omniSurfaceWater(color,view,normal,geometry.a,water,material.xyz,uv); // 先叠水、环境遮蔽与反射。
    color = omniSurfaceAir(color,view,world,geometry.a,water.a,uv); // 再叠挡在前方的云与雾。
    return omniLightning(color,world,material.a); // 最后按位置叠加闪电照明。
}

// --- 主流程：背景像素跳过几何后处理，其余像素逐层叠加，再写出颜色与覆盖标记 ---
void main() {
    bool sky = omniSkyPixel(texcoord); // 天空像素没有可追踪的表面，几何后处理对它没有意义。
    vec3 color = texture(colortex0,texcoord).rgb; // 缓冲零：前向照明与原版透明混合的结果。
    if (!sky) color = omniCompositeSurface(color,texcoord); // 背景之外的像素才做几何后处理。
    color *= 1.0-clamp(blindness,0.0,1.0); // 保留原版失明效果，让药水依然能压暗画面。
    color = omniWeather(color); // 下雨时整体压暗，天空和地形一起。
    colorOut = vec4(color,sky || texelFetch(colortex7,ivec2(gl_FragCoord.xy),0).a>=0.5 ? 1.0 : 0.0); // 把天空与精确的几何有效标记传给时间阶段。
}
#endif
