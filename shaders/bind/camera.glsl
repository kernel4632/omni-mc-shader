/*
相机绑定：把加载器的投影、视图与画面尺寸整理成一个普通结构体，供坐标换算和后期效果使用。
调用位置：需要屏幕尺寸、像素大小或相机矩阵的效果在边界调用 `bind_camera()`。
可复制示例：`vec2 texel = bind_camera().pixelSize;`
设计原因与取舍：矩阵按用途命名，通用库不必知道 `gbufferProjection` 这个名字；
  抖动值单独保留，因为时间抗锯齿要求还原坐标与投影使用同一份抖动；
  相机位置保留世界绝对坐标，效果需要相机相对坐标时自己减去它，避免两套坐标混用。
*/
#ifndef OMNI_BIND_CAMERA_INCLUDED // 只引入一次，避免结构体与函数重复定义。
#define OMNI_BIND_CAMERA_INCLUDED // 置上标记，后续再次引用直接跳过。
// 相机输入只在加载器声明文件里出现一次。
#include "/common/uniforms.glsl"

struct OmniCamera {
	mat4 projection; // 视空间到裁剪空间。
	mat4 projectionInverse; // 裁剪空间回到视空间。
	mat4 view; // 相机相对世界到视空间。
	mat4 viewInverse; // 视空间回到相机相对世界。
	mat4 previousView; // 上一帧相机变换，用于运动模糊与重投影。
	mat4 previousProjection; // 上一帧投影，用于重投影。
	mat4 shadowView; // 世界到阴影相机视空间。
	mat4 shadowProjection; // 阴影相机投影。
	mat4 shadowViewInverse; // 阴影相机视空间回到世界。
	vec2 screenSize; // 画面尺寸，单位像素。
	vec2 pixelSize; // 一个像素在零到一坐标里的大小。
	vec2 jitter; // 本帧时间抗锯齿抖动，负一到一。
	vec3 position; // 相机世界绝对位置。
	vec3 previousPosition; // 上一帧相机位置。
	float aspect; // 画面宽高比。
	float nearPlane; // 近裁剪面距离，单位米。
	float farPlane; // 远裁剪面距离，单位米。
};

// 读取本帧的相机与画面输入；只做打包，不改变任何数值。
OmniCamera bind_camera(){
	OmniCamera camera; // 待填充的结构体。
	camera.projection = gbufferProjection; // 当前投影。
	camera.projectionInverse = gbufferProjectionInverse; // 当前逆投影。
	camera.view = gbufferModelView; // 当前视图。
	camera.viewInverse = gbufferModelViewInverse; // 当前逆视图。
	camera.previousView = gbufferPreviousModelView; // 上一帧视图。
	camera.previousProjection = gbufferPreviousProjection; // 上一帧投影。
	camera.shadowView = shadowModelView; // 阴影视图。
	camera.shadowProjection = shadowProjection; // 阴影投影。
	camera.shadowViewInverse = shadowModelViewInverse; // 阴影逆视图。
	camera.screenSize = screenSize; // 像素尺寸。
	camera.pixelSize = pixelSize; // 单像素大小。
	camera.jitter = taaJitter; // 时间抗锯齿抖动。
	camera.position = cameraPosition; // 世界绝对位置。
	camera.previousPosition = previousCameraPosition; // 上一帧位置。
	camera.aspect = aspectRatio; // 宽高比。
	camera.nearPlane = near; // 近裁剪面。
	camera.farPlane = far; // 远裁剪面。
	return camera; // 返回纯数据，调用方不需要知道来源。
}
#endif // 相机绑定结束。
