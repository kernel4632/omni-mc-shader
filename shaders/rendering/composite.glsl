// 场景合成：水、反射、环境遮蔽、云雾与闪电的屏幕后处理；由 composite.fsh 引入。
// 调用位置：加载器 composite 程序；示例 `gbuffers 之后对不透明与透明像素做一次后处理`。
#ifdef OMNI_VERTEX
out vec2 texcoord; // 全屏纹理坐标。
void main() { gl_Position = ftransform(); texcoord = gl_MultiTexCoord0.xy; } // 全屏合成。
#endif
#ifdef OMNI_FRAGMENT // 仅片元阶段读取屏幕深度与辐射。
// 显式调用效果，缓冲生产消费集中在此。
#include "/rendering/buffers.glsl"
#include "/effects/antialiasing.glsl"
#include "/effects/ambient.glsl"
#include "/effects/water.glsl"
#include "/effects/cloud.glsl"
#include "/effects/fog.glsl"
#include "/effects/atmosphere.glsl"
in vec2 texcoord; // 全屏采样位置。
/* RENDERTARGETS: 6 */
layout(location=0) out vec4 colorOut; // 时间抗锯齿之前的线性结果。
// 水与反射：水面读自身深度折射，其他表面做环境遮蔽与反射。
vec3 omniSurfaceWater(vec3 color, vec3 view, vec3 normal, float category, vec4 water, vec3 material, vec2 uv) {
    if (water.a<0.0) return omniWater(color,view,normal,uv); // 水折射读取自身真实深度与不透明快照。
    if (category!=2.0) { // 手持物不应用世界屏幕遮蔽与反射。
        color = omniAmbient(color,view,normal,uv); // 普通表面的屏幕遮蔽。
        color = omniReflection(color,view,normal,material,uv); // 普通与湿润材质反射。
    }
    return color; // 返回水之前的表面颜色。
}
// 云与雾：只有存在几何或独立水面的像素才由云与雾在前方遮挡。
vec3 omniSurfaceAir(vec3 color, vec3 view, vec3 world, float category, float waterDepth, vec2 uv) {
    if (category==2.0 && waterDepth>=0.0) return color; // 手持物且没有独立水面时不叠加云与雾。
    color = omniCloud(color,omniNormalize(world),length(view)); // 云在几何之前才遮挡。
    color = omniFog(color,view,world); // 透明表面使用最近可见深度。
    return color; // 返回叠加云与雾之后的颜色。
}
// 单像素几何后处理：一次读完元数据，依次做水、反射、云、雾与闪电。
vec3 omniCompositeSurface(vec3 color, vec2 uv) {
    ivec2 pixel = clamp(ivec2(uv*vec2(viewWidth,viewHeight)),ivec2(0),ivec2(viewWidth-1.0,viewHeight-1.0)); // 元数据固定读取同一片元。
    if (texelFetch(colortex7,pixel,0).a<0.5) return color; // 无深度叠层不做几何后处理。
    vec3 view = omniSceneView(uv,false); // 近景与远景统一的真实位置。
    vec3 world = omniWorld(view); // 相机相对世界位置。
    vec4 geometry = texelFetch(colortex1,pixel,0); // 法线类别与有效性精确配对。
    vec4 material = texelFetch(colortex2,pixel,0); // 材质参数不从边缘插值。
    vec4 water = texelFetch(colortex8,pixel,0); // 水的独立法线与视空间深度。
    vec3 normal = omniNormalize((water.a<0.0?water.xyz:geometry.xyz)*2.0-1.0); // 水不再误读底层地形法线。
    color = omniSurfaceWater(color,view,normal,geometry.a,water,material.xyz,uv); // 水或环境遮蔽与反射。
    color = omniSurfaceAir(color,view,world,geometry.a,water.a,uv); // 云与雾。
    return omniLightning(color,world,material.a); // 只有匹配深度与天空光的表面参与位置相关闪电照明。
}
void main() {
    vec3 color = texture(colortex0,texcoord).rgb; // 前向照明与原版透明混合。
    if (!omniSkyPixel(texcoord)) color = omniCompositeSurface(color,texcoord); // 背景之外的像素做几何后处理。
    color *= 1.0-clamp(blindness,0.0,1.0); // 保留失明效果。
    colorOut = vec4(color,omniSkyPixel(texcoord) || texelFetch(colortex7,ivec2(gl_FragCoord.xy),0).a>=0.5 ? 1.0 : 0.0); // 覆盖层把精确元数据标记传给时间阶段。
}
#endif
