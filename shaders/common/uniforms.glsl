// 加载器输入：集中声明所有阶段共用的加载器输入变量，效果文件不重复声明这些名字。
// 调用位置：由 common/coordinates.glsl 引入，进而被各效果与绘制文件间接使用。
// 可复制示例：`texture(colortex0, uv)`、`cameraPosition`、`gbufferProjection`、`shadowLightPosition`。
#ifndef OMNI_UNIFORMS
#define OMNI_UNIFORMS
uniform sampler2D colortex0, colortex1, colortex2, colortex3; // 场景、法线、材质、不透明快照。
uniform sampler2D colortex4, colortex5, colortex6, colortex7; // 历史、历史状态、合成、原版光照。
uniform sampler2D colortex8; // 透明水表面的法线与实际视空间深度。
uniform sampler2D depthtex0, depthtex1, depthtex2; // 完整、不透明与手之前的深度。
uniform sampler2D shadowtex0; // 阴影深度。
uniform mat4 gbufferProjection, gbufferProjectionInverse; // 当前透视变换。
uniform mat4 gbufferModelView, gbufferModelViewInverse; // 当前相机变换。
uniform mat4 gbufferPreviousProjection, gbufferPreviousModelView; // 上一帧相机变换。
uniform mat4 shadowProjection, shadowModelView; // 阴影相机变换。
uniform vec3 cameraPosition, previousCameraPosition; // 相机绝对位置。
uniform vec3 sunPosition, moonPosition, shadowLightPosition, upPosition; // 视空间天体方向。
uniform vec3 fogColor, skyColor; // 加载器提供的维度环境色。
uniform float viewWidth, viewHeight, near, far; // 当前尺寸与近远裁剪面。
uniform float frameTimeCounter, frameTime, rainStrength, wetness; // 时间与天气过渡。
uniform float nightVision, blindness; // 原版状态效果。
uniform int frameCounter, worldTime, isEyeInWater; // 当前帧、游戏时间与水下状态。
uniform ivec2 eyeBrightnessSmooth; // 平滑的原版眼部照明。
uniform int heldBlockLightValue, heldBlockLightValue2; // 两只手的光源等级。
uniform vec4 entityColor; // 实体受伤或选择颜色。
#ifdef DISTANT_HORIZONS
uniform sampler2D dhDepthTex0, dhDepthTex1; // 远景独立深度。
uniform mat4 dhProjection, dhProjectionInverse, dhPreviousProjection; // 远景独立投影。
uniform float dhNearPlane, dhFarPlane; // 远景裁剪范围。
uniform int dhRenderDistance; // 远景渲染距离。
#endif
#endif
