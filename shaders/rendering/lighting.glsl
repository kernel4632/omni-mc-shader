/*
延迟快照：不透明几何画完之后，把这一帧的不透明颜色另外存一份，供后面的透明折射和屏幕反射读取。
调用位置：由各维度的绘制入口接进来，顶点入口 `world0/deferred.vsh` 定义 OMNI_VERTEX，
片元入口 `world0/deferred.fsh` 定义 OMNI_FRAGMENT，两者都用下面这两行把本文件接入：

    #define OMNI_FRAGMENT
    #include "/rendering/lighting.glsl"

为什么要有这份快照：水和玻璃等透明物体在不透明阶段之后才画，加载器不会让它们改写已经画好的不透明层。
屏幕空间反射和水的折射都要一份"没有透明物体"的不透明画面，否则两种效果会互相叠加、越算越乱。
所以这里在不透明阶段一结束，就把同一个颜色同时写进两个附件：一个继续交给合成，一个留作不透明白底。

为什么天空要重新算：加载器自带的天空色只是它自己的调色，和本项目的天空、云、氛围对不上。
天空像素在这里用同一套天空函数重算，才能让远景、反射和折射里的天空保持一致。

取舍：天空方向靠不透明阶段的远端深度反投影得到，所以这里把天空当成无限远，
用 32000.0 当作云层到相机的米制距离近似，足够让云挂在天上又不穿透地面。

提示：世界内画面还没有实机验证，先前"只有天空"的异常也还没有实机修复证据，不能当作已经修好。
*/
#ifdef OMNI_VERTEX
// 顶点阶段：加载器提供一个盖住整屏的四边形，这里只把位置透传，并记下屏幕坐标。
out vec2 texcoord; // 把屏幕纹理坐标传给片元阶段，范围从 0 到 1。
void main() {
    gl_Position = ftransform(); // 全屏四边形沿用加载器已经算好的裁剪空间位置。
    texcoord = gl_MultiTexCoord0.xy; // 取第一个纹理坐标，正好是整屏的屏幕位置。
}
#endif
#ifdef OMNI_FRAGMENT
// 缓冲编号与共用坐标函数的唯一来源。
#include "/rendering/buffers.glsl"
// 天空像素判定与视图反投影，用来在快照里补回天空。
#include "/effects/antialiasing.glsl"
// 云层着色，天空上的云和远景反射共用同一套。
#include "/effects/cloud.glsl"
// 大气散射，给天空叠上氛围颜色。
#include "/effects/atmosphere.glsl"
in vec2 texcoord; // 顶点阶段传下来的屏幕纹理坐标。
/* RENDERTARGETS: 0,3 */
layout(location=0) out vec4 scene; // 交给后续合成的不透明颜色。
layout(location=1) out vec4 snapshot; // 透明阶段动不了的原始不透明副本。

// --- 天空像素：用本项目的天空、云和氛围重算颜色 ---
// 为什么单独成函数：主流程只关心"读颜色、补天空、写两个附件"三件事，
// 天空合成的细节收在这里，读主流程时不必先弄懂云和氛围的计算。
// `textured` 是天空像素上已有的颜色：原版天空几何已关闭、零号画面清成黑色，所以这里只剩日月等贴图。
// 开启「使用资源包天空」时把它叠在天空上、云下面，资源包的太阳会被云正常挡住；关闭时丢弃，保持内置圆盘。
vec3 omniDeferredSky(vec2 uv, vec3 textured) {
    vec3 direction = omniNormalize(mat3(gbufferModelViewInverse)*omniView(uv,1.0)); // 用远端深度反投影出这个像素看向的世界方向。
    vec3 sky = omniSky(direction); // 本项目的天空底色。
#ifdef OMNI_RESOURCE_SKY
    sky += textured; // 资源包日月贴图按线性颜色叠加。
#endif
    return omniAtmosphere(omniCloud(sky,direction,32000.0),direction); // 先画天空，再叠云，最后加氛围。
}

// --- 主流程：读不透明颜色，补回天空，写进颜色与快照两个附件 ---
void main() {
    vec3 color = texture(colortex0,texcoord).rgb; // 取不透明阶段已经画好的颜色。
    if (omniSkyPixel(texcoord)) color = omniDeferredSky(texcoord,color); // 天空像素改用本项目天空，按选项保留资源包日月贴图。
    scene = vec4(color,1.0); // 颜色附件继续交给后续合成。
    snapshot = vec4(color,1.0); // 快照附件留一份同样的内容，供透明阶段读取。
}
#endif
