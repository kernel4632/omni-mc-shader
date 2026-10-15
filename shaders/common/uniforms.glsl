/*
加载器输入：集中声明所有绘制阶段共用的加载器输入量，供效果与绘制文件直接使用。

这是这些名字的唯一来源：同一个名字只在这里出现一次，改一处就够，别的文件直接引用它。
集中放在 common/ 下，坐标、光照、远景等模块都从这里取，不再各自重复声明。

// 调用位置：由 common/coordinates.glsl 引入，也可以由效果文件直接引用。
这些名字在被引用处直接使用，不需要在别处再声明一遍。

可复制示例（四行都可直接粘进效果文件）：
  `texture(colortex0, uv)` 取场景线性颜色；
  `gbufferModelViewInverse * vec4(view, 1.0)` 把视空间位置转成世界位置；
  `shadowLightPosition` 是指向太阳或月亮的视空间方向；
  `length(cameraPosition - previousCameraPosition)` 是相机位移，单位米。

设计原因与取舍：这些量全部由 Iris 加载器每帧填入，光影无权改名、增删或换类型。
集中在一处，避免同一个名字在多个文件里各写一遍、类型写岔。
按加载器给出的顺序平铺声明，不做类型或用途的包装层，接手者从上往下一次看完。
*/
#ifndef OMNI_UNIFORMS // 这份声明只引入一次，避免重复引入时重复声明。
#define OMNI_UNIFORMS // 置上标记，后续再次引用时直接跳过。

// --- 中间画面：加载器分配的离屏颜色附件，用途由 rendering/buffers.glsl 统一约定 ---
uniform sampler2D colortex0, colortex1, colortex2, colortex3; // 零场景线性颜色、一视空间法线与几何类别、二材质参数、三不透明颜色快照。
uniform sampler2D colortex4, colortex5, colortex6, colortex7; // 四上一帧颜色历史、五历史状态、六抗锯齿前合成色、七原版光照数据。
uniform sampler2D colortex8; // 透明水表面的编码法线与负的实际视空间深度，零表示没有水表面。

// --- 深度：屏幕每个像素到相机的距离，用来判遮挡、重建位置和分景深 ---
uniform sampler2D depthtex0, depthtex1, depthtex2; // 依次是完全深度、不含半透明的深度、去掉手持物的深度；非线性的零到一深度值。

// --- 阴影：光源视角下每个位置的最近表面深度，比较它可判断某点是否被遮挡 ---
uniform sampler2D shadowtex0; // 太阳或月亮视角的阴影深度，接收点比它更远就算处在阴影中。

// --- 坐标变换：加载器每帧更新的矩阵，负责视空间、世界空间与裁剪空间之间互换 ---
uniform mat4 gbufferProjection, gbufferProjectionInverse; // 当前帧投影与其逆矩阵：视空间到裁剪空间，以及反向重建位置。
uniform mat4 gbufferModelView, gbufferModelViewInverse; // 当前帧相机变换与其逆矩阵：相机相对世界到视空间，以及反向。
uniform mat4 gbufferPreviousProjection, gbufferPreviousModelView; // 上一帧的投影与相机变换，用来算运动向量和重投影历史。
uniform mat4 shadowProjection, shadowModelView; // 阴影相机把世界点投到光源视角，做阴影比较时用。

// --- 相机位置与天体方向：绝对位置用于跨帧对齐，天体方向用于光照与天空 ---
uniform vec3 cameraPosition, previousCameraPosition; // 相机世界绝对位置与上一帧位置，单位米，用于重投影和判断点距。
uniform float eyeAltitude; // 眼睛相对海平面的高度，单位米（约等于格）；换成公里加大气底半径，让高空看天空时结果正确。
uniform vec3 sunPosition, moonPosition, shadowLightPosition, upPosition; // 依次是太阳方向、月亮方向、当前阴影光源方向、世界上方方向，都是视空间单位向量。

// --- 环境色：加载器按当前维度提供的颜色，用来做雾与天空的混合 ---
uniform vec3 fogColor, skyColor; // 当前维度的雾色与天色，显示空间颜色（sRGB）；进入光照或线性混合前需先转线性。

// --- 屏幕尺寸与裁剪面：重建位置、屏幕抖动和深度换算都要用 ---
uniform float viewWidth, viewHeight, near, far; // 当前渲染分辨率，单位像素；近裁剪面与远裁剪面距离，单位米。

// --- 时间与天气：驱动动画、雨雪过渡和循环效果 ---
uniform float frameTimeCounter, frameTime, rainStrength, wetness; // 累计运行秒数、单帧秒数、降雨强度与湿润度，后两个范围零到一。

// --- 玩家状态：原版效果强度与照明等级，用来让画面跟随游戏玩法 ---
uniform float nightVision, blindness; // 夜视和失明的强度，范围零到一。
uniform int frameCounter, worldTime, worldDay, isEyeInWater; // 帧序号、世界时间（单位游戏刻）、世界天数（用于季节）、眼睛是否在水中（零无、一水、二岩浆）。
uniform ivec2 eyeBrightnessSmooth; // 平滑后的眼部亮度，横轴方块光等级、纵轴天空光等级，范围零到二百四十。
uniform int heldBlockLightValue, heldBlockLightValue2; // 主手与副手方块光源等级，范围零到十五。
uniform vec4 entityColor; // 实体受伤或受击时叠加的染色，四通道颜色。

// --- 远景：仅当加载远景模组时存在，缺省时退回上面那套近景输入 ---
#ifdef DISTANT_HORIZONS // 没有远景模组时不声明下面这些名字。
uniform sampler2D dhDepthTex0, dhDepthTex1; // 远景自己的完整深度与不含半透明深度，同样是非线性的零到一深度值。
uniform mat4 dhProjection, dhProjectionInverse, dhPreviousProjection; // 远景投影、它的逆矩阵、以及上一帧投影。
uniform float dhNearPlane, dhFarPlane; // 远景的近裁剪面与远裁剪面距离，单位米。
uniform int dhRenderDistance; // 远景渲染距离，单位区块。
#endif // 远景输入声明结束。
#endif
