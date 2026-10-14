// 场景合成：反射、水、环境遮蔽、云雾与闪电；示例 composite 引入。
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
void main() {
    vec4 sceneInput = texture(colortex0,texcoord); // 前向照明与原版透明混合。
    vec3 color = sceneInput.rgb; // 覆盖层颜色不改变底层几何协议。
    if (!omniSkyPixel(texcoord)) {
        ivec2 pixel = clamp(ivec2(texcoord*vec2(viewWidth,viewHeight)),ivec2(0),ivec2(viewWidth-1.0,viewHeight-1.0)); // 元数据固定读取同一片元。
        vec4 surfaceMeta = texelFetch(colortex7,pixel,0); // 类别与有效性不使用线性过滤。
        bool overlay = surfaceMeta.a<0.5; // 无深度叠层由独立附件标记。
        vec3 view = omniSceneView(texcoord,false), world = omniWorld(view); // 近景与远景统一的真实位置。
        vec4 geometry = texelFetch(colortex1,pixel,0); // 法线类别与有效性精确配对。
        vec4 material = texelFetch(colortex2,pixel,0); // 材质参数不从边缘插值。
        if (!overlay) {
            vec4 water = texelFetch(colortex8,pixel,0); // 水的独立法线与视空间深度。
            vec3 normal = omniNormalize((water.a<0.0?water.xyz:geometry.xyz)*2.0-1.0); // 水不再误读底层地形法线。
            if (water.a<0.0) color = omniWater(color,view,normal,texcoord); // 水折射读取自身真实深度与不透明快照。
            else if (geometry.a!=2.0) {
                color = omniAmbient(color,view,normal,texcoord); // 手持物不应用世界屏幕遮蔽。
                color = omniReflection(color,view,normal,material.xyz,texcoord); // 普通与湿润材质反射。
            }
            if (geometry.a!=2.0 || water.a<0.0) {
                color = omniCloud(color,omniNormalize(world),length(view)); // 云在几何之前才遮挡。
                color = omniFog(color,view,world); // 透明表面使用最近可见深度。
            }
            color = omniLightning(color,world,material.a); // 只有匹配深度与天空光的表面参与位置相关闪电照明。
        }
    }
    color *= 1.0-clamp(blindness,0.0,1.0); // 保留失明效果。
    colorOut = vec4(color,omniSkyPixel(texcoord) || texelFetch(colortex7,ivec2(gl_FragCoord.xy),0).a>=0.5 ? 1.0 : 0.0); // 覆盖层把精确元数据标记传给时间阶段。
}
#endif
