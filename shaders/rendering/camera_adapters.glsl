/*
相机坐标兼容层：Eclipse 的投影函数直接读全局矩阵，宿主层用同名重载补齐。
调用位置：由 `rendering/composite_shared.glsl` 在片元全局量声明之后引入，所有合成程序可用。
可复制示例：`vec3 screen = toClipSpace3(viewPos);`
设计原因与取舍：参考函数不带矩阵参数，库函数要求显式传入；本文件只做全局量到显式参数的转发，
    不改动投影算法。远景分支在默认配置关闭，按参考默认分支统一走近景矩阵。
*/
#ifndef OMNI_RENDER_CAMERA_ADAPTERS_INCLUDED
#define OMNI_RENDER_CAMERA_ADAPTERS_INCLUDED
// 相机投影函数在生成库，宿主兼容层直接引用。
#include "/omni-gfx/common/camera.glsl"

// 投影到裁剪空间：参考直接读 `gbufferProjection`。
vec3 toClipSpace3(vec3 viewSpacePosition){ return ogxToClipSpace3(viewSpacePosition, gbufferProjection); }
// 裁剪空间回到视空间：参考直接读 `gbufferProjectionInverse`。
vec3 toScreenSpace(vec3 p){ return ogxToScreenSpace(p, gbufferProjectionInverse); }
// 只要方向时少做一次透视除法。
vec3 toScreenSpaceVector(vec3 p){ return ogxToScreenSpaceVector(p, gbufferProjectionInverse); }
// 视空间转到相机相对世界。
vec3 toWorldSpace(vec3 p3){ return ogxToWorldSpace(p3, gbufferModelViewInverse); }
// 再补相机世界坐标。
vec3 toWorldSpaceCamera(vec3 p3){ return ogxToWorldSpaceCamera(p3, gbufferModelViewInverse, cameraPosition); }
// 转到阴影相机视空间。
vec3 toShadowSpace(vec3 p3){ return ogxToShadowSpace(p3, gbufferModelViewInverse, shadowModelView); }
// 再乘阴影投影的对角项，得到阴影贴图坐标。
vec3 toShadowSpaceProjected(vec3 p3){ return ogxToShadowSpaceProjected(p3, gbufferModelViewInverse, shadowModelView, shadowProjection); }
// 参考的远景版本在默认配置关闭，统一走近景逆投影。
vec3 toScreenSpace_DH(vec2 texcoord, float depth, float dhDepth){
	vec3 result = vec3(0.0); // 参考以零初始化，再按深度选择近景或远景矩阵。
	result = ogxToScreenSpaceDistant(texcoord, depth, dhDepth, gbufferProjectionInverse, gbufferProjectionInverse);
	return result;
}
// 参考的远景裁剪同样默认走近景投影。
vec3 toClipSpace3_DH(vec3 viewSpacePosition, bool depthCheck){ return ogxToClipSpace3Distant(viewSpacePosition, depthCheck, gbufferProjection, gbufferProjection); }
// 参考在默认配置直接返回原矩阵。
mat4 DH_shadowProjectionTweak(mat4 projection){ return projection; }
// 屏幕坐标到视空间方向。
vec3 screen_to_view_space(vec3 screenPos, bool depthCheck){ return ogxScreenToViewSpace(screenPos, gbufferProjectionInverse); }
// 视空间到屏幕坐标。
vec3 view_to_screen_space(vec3 viewPos, bool depthCheck){ return ogxViewToScreenSpace(viewPos, gbufferProjection); }
// 参考的第二种屏幕还原，默认走近景逆投影。
vec3 toScreenSpace2(vec3 p, bool depthCheck){ return ogxToScreenSpace2(p, depthCheck, gbufferProjectionInverse, gbufferProjectionInverse); }
// 非线性深度快速换线性。
float invertLinearizeDepthFast(float z){ return ogxInvertLinearizeDepthFast(z, near, far); }
// 手部深度换算，固定手部深度由宏提供。
float convertHandDepth_3(float depth, bool hand){ return ogxConvertHandDepth3(depth, hand, MC_HAND_DEPTH); }

#endif // 相机兼容层结束。
