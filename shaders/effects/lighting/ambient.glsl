/*
环境光与遮蔽：反射阴影图全局光的时间与空间滤波，以及地平线环境遮蔽，按 iterationT 原算法移植。
调用位置：延迟一号主体算全局光时间滤波时调用 `GI_TemporalFilter`；
    延迟二号主体算空间滤波与遮蔽时调用 `GI_SpatialFilter`、`GroundTruthBasedAmbientOcclusion`；
    合成主体把遮蔽乘到最终颜色上并做多弹射补偿时调用 `GTAOMultiBounce`。
可复制示例：
    `vec3 gi = GI_SpatialFilter(dist, normal, viewDir);`
    `float ao = GroundTruthBasedAmbientOcclusion(viewPos, -viewDir, normal);`
    `vec3 ao = GTAOMultiBounce(gi.a, gbuffer.albedo);`
设计原因与取舍：
    全局光只在需要时才编译：时间滤波与空间滤波各自放在对应程序宏里，避免在别的程序里凭空多出一堆采样。
    反射阴影图全局光与地平线遮蔽互相独立，各自带开关，关闭时整支计算不编译。
    调用前提（iterationT 原样保留）：冻结 `OMNI_DEFERRED1_PASS` 的程序要先声明 `shadowtex0`、`shadowtex1`、
    `shadowcolor0`、`shadowcolor1` 与 `texelCoord`、`texCoord`，并让材质编号 `MATID_ENTITIES_PLAYER` 可见；
    `OMNI_DEFERRED2_PASS` 的程序要先声明 `gbufferProjection`、`depthtex1`、`texCoord`；
    坐标换算按合同要先引入定义 `OMNI_TAA` 的效果文件。为什么这里不直接引入 `effects/material.glsl`：
    那份文件带只在几何阶段存在的贴图取样器，延迟程序引不动，材质编号由绘制主体保证可见。
    末地把延迟程序重新排序（时间滤波在二号、空间滤波在四号），所以本文件的编译条件同时认末地对应的程序宏。
*/
#ifndef OMNI_AMBIENT_INCLUDED
#define OMNI_AMBIENT_INCLUDED
// @effect {"label":{"zh_cn":"环境光与遮蔽","en_us":"GI & AO"}}
// @option {"label":{"zh_cn":"全局光反射阴影图","en_us":"GI RSM"},"description":{"zh_cn":"用阴影图里可见的表面做一次屏幕外反弹，给阴影补光。","en_us":"Bounces light from surfaces visible in the shadow map to fill in shadows."}}
#define OMNI_GI_RSM
// @option {"label":{"zh_cn":"全局光质量","en_us":"GI Quality"},"description":{"zh_cn":"每个像素的反弹采样次数，越高越干净也越慢。","en_us":"Bounce samples per pixel; higher is cleaner and slower."},"slider":true}
#define OMNI_GI_QUALITY 16 // [4 8 12 16 24 32 48 64 96 128]
// @option {"label":{"zh_cn":"全局光半径","en_us":"GI Radius"},"description":{"zh_cn":"反弹搜索的半径，越大补光越广。","en_us":"Search radius of the bounce; larger spreads more light."},"slider":true}
#define OMNI_GI_RADIUS 7.0 // [1.0 1.5 2.0 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 70.0 100.0]
// @option {"label":{"zh_cn":"全局光亮度","en_us":"GI Brightness"},"description":{"zh_cn":"反弹补光的整体亮度。","en_us":"Overall brightness of the bounce light."},"slider":true}
#define OMNI_GI_BRIGHTNESS 1.0 // [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.6 1.8 2.0 2.5 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 70.0 100.0]
// @option {"label":{"zh_cn":"全局光渲染分辨率","en_us":"GI Render Resolution"},"description":{"zh_cn":"全局光在多少分辨率上算，半分辨率更省。","en_us":"Resolution the GI is computed at; half is cheaper."},"values":{"0.25":{"zh_cn":"四分之一","en_us":"Quarter"},"0.5":{"zh_cn":"一半","en_us":"Half"}}}
#define OMNI_GI_RENDER_RESOLUTION 0.5 // [0.25 0.5]
// @option {"label":{"zh_cn":"全局光衰减","en_us":"GI Falloff"},"description":{"zh_cn":"反弹随距离衰减的指数，越大越只影响近处。","en_us":"Distance falloff exponent of the bounce; higher keeps it near."},"slider":true}
#define OMNI_GI_FALLOFF 1.1 // [1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label":{"zh_cn":"全局光天光衰减","en_us":"GI Skylight Falloff"},"description":{"zh_cn":"反弹随天空光等级衰减，避免洞穴里也被补到光。","en_us":"Fades the bounce with skylight so caves are not lit."}}
#define OMNI_GI_SKYLIGHT_FALLOFF
// @option {"label":{"zh_cn":"关闭手部全局光","en_us":"Disable Hand GI"},"description":{"zh_cn":"手不接收屏幕外的反弹补光。","en_us":"Keeps the hand from receiving off-screen bounce light."}}
//#define OMNI_DISABLE_HAND_GI
// @option {"label":{"zh_cn":"关闭手部全局光速度","en_us":"Disable Hand GI Velocity"},"description":{"zh_cn":"手不参与全局光的历史重投影，减少手的拖影。","en_us":"Excludes the hand from GI history reprojection to reduce smearing."}}
//#define OMNI_DISABLE_HAND_GI_VELOCITY
// @option {"label":{"zh_cn":"关闭玩家全局光","en_us":"Disable Player GI"},"description":{"zh_cn":"玩家角色不接收屏幕外的反弹补光。","en_us":"Keeps the player from receiving off-screen bounce light."}}
//#define OMNI_DISABLE_PLAYER_GI
// @option {"label":{"zh_cn":"关闭玩家全局光速度","en_us":"Disable Player GI Velocity"},"description":{"zh_cn":"玩家不参与全局光的历史重投影。","en_us":"Excludes the player from GI history reprojection."}}
//#define OMNI_DISABLE_PLAYER_GI_VELOCITY
// @option {"label":{"zh_cn":"地平线遮蔽","en_us":"GTAO"},"description":{"zh_cn":"地面真相环境遮蔽，墙角缝隙变暗。","en_us":"Ground-truth ambient occlusion; darkens corners and creases."}}
#define OMNI_GTAO
// @option {"label":{"zh_cn":"遮蔽质量","en_us":"GTAO Quality"},"description":{"zh_cn":"环绕视线的切片数，越高越稳也越慢。","en_us":"Slices around the view; higher is steadier and slower."},"slider":true}
#define OMNI_GTAO_QUALITY 3 // [1 2 3 4 5 6 8 10 15 20]
// @option {"label":{"zh_cn":"遮蔽切片质量","en_us":"GTAO Slice Quality"},"description":{"zh_cn":"每个切片的搜索步数。","en_us":"Search steps per slice."},"slider":true}
#define OMNI_GTAO_SLICE_QUALITY 3 // [1 2 3 4 5 6 8 10 15 20]
// @option {"label":{"zh_cn":"遮蔽半径模式","en_us":"GTAO Radius Mode"},"description":{"zh_cn":"零为世界半径，一为屏幕半径。","en_us":"Zero uses world radius, one uses screen radius."},"values":{"0":{"zh_cn":"世界","en_us":"World"},"1":{"zh_cn":"屏幕","en_us":"Screen"}}}
#define OMNI_GTAO_RADIUS_MODE 0 // [0 1]
// @option {"label":{"zh_cn":"遮蔽世界半径","en_us":"GTAO World Radius"},"description":{"zh_cn":"世界半径模式下的取样半径，单位方块。","en_us":"Sample radius in world-radius mode, in blocks."},"slider":true}
#define OMNI_GTAO_WORLD_RADIUS 2.0 // [0.5 0.7 1.0 1.5 2.0 3.0 5.0 7.0 10.0 15.0 20.0]
// @option {"label":{"zh_cn":"遮蔽屏幕半径","en_us":"GTAO Screen Radius"},"description":{"zh_cn":"屏幕半径模式下的取样半径，单位屏幕比例。","en_us":"Sample radius in screen-radius mode, in screen fraction."},"slider":true}
#define OMNI_GTAO_SCREEN_RADIUS 0.05 // [0.001 0.0015 0.002 0.003 0.005 0.007 0.01 0.015 0.02 0.03 0.05 0.07 0.1 0.15 0.2 0.3 0.5]
// @option {"label":{"zh_cn":"遮蔽最大半径","en_us":"GTAO Max Radius"},"description":{"zh_cn":"屏幕半径上限，避免近处取样范围过大。","en_us":"Cap on the screen radius so near geometry does not over-sample."},"slider":true}
#define OMNI_GTAO_MAX_RADIUS 0.1 // [0.01 0.015 0.02 0.03 0.05 0.07 0.1 0.15 0.2 0.3 0.5]
// @option {"label":{"zh_cn":"遮蔽衰减起点","en_us":"GTAO Falloff Start"},"description":{"zh_cn":"远处样本开始衰减的位置比例。","en_us":"Fraction at which far samples start to fade."},"slider":true}
#define OMNI_GTAO_FALLOFF_START 0.7 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"遮蔽强度","en_us":"GTAO Strength"},"description":{"zh_cn":"遮蔽压暗的强度，取零等于关闭。","en_us":"Darkening strength of the AO; zero disables it."},"slider":true}
#define OMNI_GTAO_STRENGTH 0.95 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.525 0.55 0.575 0.6 0.625 0.65 0.675 0.7 0.725 0.75 0.775 0.8 0.85 0.9 0.95 1.0]
// @option {"label":{"zh_cn":"遮蔽多弹射","en_us":"GTAO Multibounce"},"description":{"zh_cn":"按表面底色给遮蔽做一次多弹射补偿，暗部不会压死。","en_us":"Multi-bounce correction using albedo so dark areas do not crush."}}
#define OMNI_GTAO_MULTIBOUNCE
// 相对坐标、数学、噪声与共享效果按下述顺序引入；本文件末尾的算法只在这里定义一次。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
#include "/effects/clarity/antialiasing.glsl"
#include "/common/coordinates.glsl"
#include "/common/noise.glsl"
#include "/effects/shadow/shadow.glsl"
#ifdef OMNI_GI_RSM // 只有打开全局光才需要下面的函数。
////////////////////PROGRAM_GI_0////////////////////////////////////////////////////////////////////
////////////////////PROGRAM_GI_0////////////////////////////////////////////////////////////////////
#if (defined OMNI_DEFERRED1_PASS && !defined OMNI_END) || (defined OMNI_END && defined OMNI_DEFERRED2_PASS) // 主世界在延迟一号、末地在延迟二号做反射阴影图与时间滤波。
// 反射阴影图反弹：从阴影图里可见的表面取光照与底色，按法线朝向和距离估计给当前点补一份光。
vec3 RSM(vec3 viewPos, vec3 normal){
	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz; // 视空间位置换到世界空间。
	vec3 shadowPosition = ShadowScreenPos_From_WorldPos_WithoutZScaling(worldPos); // 世界位置投到阴影图坐标。
	#ifdef OMNI_END // 末地用末地版阴影相机。
		vec3 shadowNormal = mat3(shadowModelViewEnd) * mat3(gbufferModelViewInverse) * normal; // 法线转到末地阴影相机空间。
	#else // 主世界与下界用主阴影相机。
		vec3 shadowNormal = mat3(shadowModelView) * mat3(gbufferModelViewInverse) * normal; // 法线转到阴影相机空间。
	#endif
	float pixelOffset = OMNI_GI_RADIUS * shadowProjection[0][0]; // 搜索半径换成阴影图像素。
	float zScale = 1.0 / shadowProjection[0][0]; // 阴影深度的缩放系数。
	vec2 noise = BlueNoiseTemporal(); // 每帧变化的蓝噪声，用来抖动采样方向。
	const mat2 rotMat = mat2(cos(goldenAngle), sin(goldenAngle), -sin(goldenAngle), cos(goldenAngle)); // 螺旋采样旋转矩阵。
	float angle = noise.x * TAU; // 起始旋转角。
	vec2 rot = vec2(cos(angle), sin(angle)); // 起始方向。
	const float steps = OMNI_GI_QUALITY; // 采样次数。
	const float rSteps = 1.0 / steps; // 采样次数倒数。
	vec3 rsm = vec3(0.0); // 累积的反弹颜色。
	for (float i = 0.0; i < steps; i++){ // 螺旋逐点采样。
		rot *= rotMat; // 每步旋转一点。
		float r = (i + noise.y) * rSteps; // 归一化半径。
		vec2 offset = rot * r * pixelOffset; // 屏幕偏移。
		vec2 offsetPosition = shadowPosition.xy + offset; // 采样点的阴影图坐标。
		vec2 sampleCoord = DistortShadowScreenPos(offsetPosition); // 还原畸变后的坐标。
		ivec2 sampleTexelcoord = ivec2(shadowMapResolution * sampleCoord); // 换成纹素。
		#ifdef MC_GL_VENDOR_NVIDIA // 英伟达用一号阴影深度。
			float sampleDepth = texelFetch(shadowtex1, sampleTexelcoord, 0).x; // 读一号深度。
		#else // 其他显卡用零号阴影深度。
			float sampleDepth = texelFetch(shadowtex0, sampleTexelcoord, 0).x; // 读零号深度。
		#endif
		if (sampleDepth == 0.0 || sampleDepth >= 1.0) continue; // 没有几何或超出范围就跳过。
		vec3 sampleVector = vec3(offsetPosition, sampleDepth) - shadowPosition; // 采样点相对当前点。
		sampleVector *= vec3(zScale, zScale, -zScale * 2.0); // 修正到统一的深度尺度。
		vec3 sampleDir = normalize(sampleVector); // 采样方向。
		float NdotV = dot(sampleDir, shadowNormal); // 当前点法线与采样方向的夹角余弦。
		if (NdotV <= 0.0) continue; // 背对采样点不接收。
		vec4 sampleData = texelFetch(shadowcolor1, sampleTexelcoord, 0); // 读阴影图里的法线与天光。
		vec3 sampleNormal = sampleData.rgb * 2.0 - 1.0; // 还原采样点法线。
		float SNdotV = dot(-sampleDir, sampleNormal) * 1.004 - 0.004; // 采样点法线与入射方向的夹角余弦，留一点余量。
		if (SNdotV < 0.0) continue; // 背对方向不发光。
		vec3 sampleAlbedo = GammaToLinear(texelFetch(shadowcolor0, sampleTexelcoord, 0).rgb); // 采样点底色转线性。
		sampleVector.z *= 1.5; // 深度方向加权，避免细长表面贡献过大。
		float sampleDist = length(sampleVector); // 采样距离。
		float distFalloff = pow(sampleDist + 0.035, -OMNI_GI_FALLOFF) * fsqrt(1.0 - r); // 距离衰减与中心加权。
		#if defined OMNI_SUNLIGHT_LEAK_FIX && !defined OMNI_END // 主世界做阳光泄漏修正。
			float mcLightingMask = saturate(sampleData.a * 15.0 + float(isEyeInWater == 1)); // 只有接到天光或在水里才补光。
			rsm += sampleAlbedo * (NdotV * SNdotV * distFalloff * mcLightingMask); // 加一份受遮挡限制的反弹。
		#else // 末地或关闭修正时不做遮罩。
			rsm += sampleAlbedo * (NdotV * SNdotV * distFalloff); // 直接累加反弹。
		#endif
	}
	rsm *= rSteps * OMNI_GI_RADIUS * 0.1; // 平均并按半径缩放。
	return rsm; // 返回反弹颜色。
}
#ifdef DISTANT_HORIZONS // 有远景模组时相机速度要区分远景。
// 算这个像素相对上一帧的屏幕位移；远景像素用远景矩阵，近景像素用普通矩阵。
vec2 CalculateCameraVelocity(vec2 coord, float depth, bool isDH){
	vec3 screenPos = vec3(coord, depth); // 屏幕坐标加深度。
	vec3 projection = vec3(screenPos * 2.0 - 1.0); // 换到负一到一。
	if (isDH){ // 远景像素。
		projection = (vec3(vec2(dhProjectionInverse[0].x, dhProjectionInverse[1].y) * projection.xy, 0.0) + dhProjectionInverse[3].xyz) / (dhProjectionInverse[2].w * projection.z + dhProjectionInverse[3].w); // 远景逆投影到视空间。
		projection = mat3(gbufferModelViewInverse) * projection + gbufferModelViewInverse[3].xyz; // 视空间转世界。
		projection += cameraPosition - previousCameraPosition; // 加上相机的世界位移。
		projection = mat3(gbufferPreviousModelView) * projection + gbufferPreviousModelView[3].xyz; // 世界转上一帧视空间。
	}else{ // 近景像素。
		projection = (vec3(vec2(gbufferProjectionInverse[0].x, gbufferProjectionInverse[1].y) * projection.xy, 0.0) + gbufferProjectionInverse[3].xyz) / (gbufferProjectionInverse[2].w * projection.z + gbufferProjectionInverse[3].w); // 近景逆投影到视空间。
		#if defined OMNI_DISABLE_HAND_GI_VELOCITY && defined OMNI_DISABLE_PLAYER_GI_VELOCITY // 手和玩家都不参与重投影。
			float materialIDs = floor(texelFetch(colortex5, ivec2(floor(coord * screenSize)), 0).b * 255.0); // 读材质编号。
			if (depth >= 0.7 && materialIDs != MATID_ENTITIES_PLAYER){ // 非玩家且较远的像素。
				projection = mat3(gbufferModelViewInverse) * projection + gbufferModelViewInverse[3].xyz; // 视空间转世界。
				projection += cameraPosition - previousCameraPosition; // 加相机位移。
				projection = mat3(gbufferPreviousModelView) * projection + gbufferPreviousModelView[3].xyz; // 转上一帧视空间。
			}
		#elif defined OMNI_DISABLE_HAND_GI_VELOCITY // 只有手不参与。
			if (depth >= 0.7){ // 较远的像素才重投影。
				projection = mat3(gbufferModelViewInverse) * projection + gbufferModelViewInverse[3].xyz; // 视空间转世界。
				projection += cameraPosition - previousCameraPosition; // 加相机位移。
				projection = mat3(gbufferPreviousModelView) * projection + gbufferPreviousModelView[3].xyz; // 转上一帧视空间。
			}
		#elif defined OMNI_DISABLE_PLAYER_GI_VELOCITY // 只有玩家不参与。
			float materialIDs = floor(texelFetch(colortex5, ivec2(floor(coord * screenSize)), 0).b * 255.0); // 读材质编号。
			if (materialIDs != MATID_ENTITIES_PLAYER){ // 非玩家像素。
				if (depth < 0.7){ // 手部像素只加一个固定位移。
					projection += (gbufferPreviousModelView[3].xyz - gbufferModelView[3].xyz) * MC_HAND_DEPTH; // 手部固定深度偏移。
				}else{ // 其他近景像素正常重投影。
					projection = mat3(gbufferModelViewInverse) * projection + gbufferModelViewInverse[3].xyz; // 视空间转世界。
					projection += cameraPosition - previousCameraPosition; // 加相机位移。
					projection = mat3(gbufferPreviousModelView) * projection + gbufferPreviousModelView[3].xyz; // 转上一帧视空间。
				}
			}
		#else // 都参与重投影。
			if (depth < 0.7){ // 手部像素只加一个固定位移。
				projection += (gbufferPreviousModelView[3].xyz - gbufferModelView[3].xyz) * MC_HAND_DEPTH; // 手部固定深度偏移。
			}else{ // 其他近景像素正常重投影。
				projection = mat3(gbufferModelViewInverse) * projection + gbufferModelViewInverse[3].xyz; // 视空间转世界。
				projection += cameraPosition - previousCameraPosition; // 加相机位移。
				projection = mat3(gbufferPreviousModelView) * projection + gbufferPreviousModelView[3].xyz; // 转上一帧视空间。
			}
		#endif
	}
	projection = (vec3(gbufferPreviousProjection[0].x, gbufferPreviousProjection[1].y, gbufferPreviousProjection[2].z) * projection + gbufferPreviousProjection[3].xyz) / -projection.z * 0.5 + 0.5; // 投回上一帧屏幕坐标。
	return coord - projection.xy; // 返回屏幕位移。
}
#else // 没有远景模组时的简化版。
// 算这个像素相对上一帧的屏幕位移，不需要区分远景。
vec2 CalculateCameraVelocity(vec2 coord, float depth){
	vec3 projection = vec3(coord, depth) * 2.0 - 1.0; // 屏幕坐标换到负一到一。
	projection = (vec3(vec2(gbufferProjectionInverse[0].x, gbufferProjectionInverse[1].y) * projection.xy, 0.0) + gbufferProjectionInverse[3].xyz) / (gbufferProjectionInverse[2].w * projection.z + gbufferProjectionInverse[3].w); // 逆投影到视空间。
	#if defined OMNI_DISABLE_HAND_GI_VELOCITY && defined OMNI_DISABLE_PLAYER_GI_VELOCITY // 手和玩家都不参与。
		float materialIDs = floor(texelFetch(colortex5, ivec2(floor(coord * screenSize)), 0).b * 255.0); // 读材质编号。
		if (depth >= 0.7 && materialIDs != MATID_ENTITIES_PLAYER){ // 非玩家且较远。
			projection = mat3(gbufferModelViewInverse) * projection + gbufferModelViewInverse[3].xyz; // 视空间转世界。
			projection += cameraPosition - previousCameraPosition; // 加相机位移。
			projection = mat3(gbufferPreviousModelView) * projection + gbufferPreviousModelView[3].xyz; // 转上一帧视空间。
		}
	#elif defined OMNI_DISABLE_HAND_GI_VELOCITY // 只有手不参与。
		if (depth >= 0.7){ // 较远像素才重投影。
			projection = mat3(gbufferModelViewInverse) * projection + gbufferModelViewInverse[3].xyz; // 视空间转世界。
			projection += cameraPosition - previousCameraPosition; // 加相机位移。
			projection = mat3(gbufferPreviousModelView) * projection + gbufferPreviousModelView[3].xyz; // 转上一帧视空间。
		}
	#elif defined OMNI_DISABLE_PLAYER_GI_VELOCITY // 只有玩家不参与。
		float materialIDs = floor(texelFetch(colortex5, ivec2(floor(coord * screenSize)), 0).b * 255.0); // 读材质编号。
		if (materialIDs != MATID_ENTITIES_PLAYER){ // 非玩家像素。
			if (depth < 0.7){ // 手部像素固定位移。
				projection += (gbufferPreviousModelView[3].xyz - gbufferModelView[3].xyz) * MC_HAND_DEPTH; // 手部固定深度偏移。
			}else{ // 其他像素正常重投影。
				projection = mat3(gbufferModelViewInverse) * projection + gbufferModelViewInverse[3].xyz; // 视空间转世界。
				projection += cameraPosition - previousCameraPosition; // 加相机位移。
				projection = mat3(gbufferPreviousModelView) * projection + gbufferPreviousModelView[3].xyz; // 转上一帧视空间。
			}
		}
	#else // 都参与。
		if (depth < 0.7){ // 手部像素固定位移。
			projection += (gbufferPreviousModelView[3].xyz - gbufferModelView[3].xyz) * MC_HAND_DEPTH; // 手部固定深度偏移。
		}else{ // 其他像素正常重投影。
			projection = mat3(gbufferModelViewInverse) * projection + gbufferModelViewInverse[3].xyz; // 视空间转世界。
			projection += cameraPosition - previousCameraPosition; // 加相机位移。
			projection = mat3(gbufferPreviousModelView) * projection + gbufferPreviousModelView[3].xyz; // 转上一帧视空间。
		}
	#endif
	projection = (vec3(gbufferPreviousProjection[0].x, gbufferPreviousProjection[1].y, gbufferPreviousProjection[2].z) * projection + gbufferPreviousProjection[3].xyz) / -projection.z * 0.5 + 0.5; // 投回上一帧屏幕坐标。
	return coord - projection.xy; // 返回屏幕位移。
}
#endif
// 全局光时间滤波：把本帧反射阴影图与历史帧按法线和深度做双向插值，抑制闪烁。
vec4 GI_TemporalFilter(){
	vec4 prev = texelFetch(colortex2, texelCoord, 0); // 先取历史像素。
	vec2 coord = texCoord / OMNI_GI_RENDER_RESOLUTION; // 全局光渲染分辨率下的坐标。
	if (saturate(coord) == coord){ // 只在有效范围内处理。
		ivec2 texel = ivec2(coord * screenSize); // 对应的屏幕纹素。
		float currDepth = texelFetch(depthtex1, texel, 0).x; // 本帧不透明深度。
		#ifdef DISTANT_HORIZONS // 有远景时天空像素改读远景深度。
			bool isDH = false; // 标记是否远景像素。
			if (currDepth == 1.0){ // 天空像素。
				currDepth = texelFetch(dhDepthTex0, texel, 0).x; // 改读远景深度。
				isDH = true; // 标记为远景。
			}
		#endif
		if (currDepth < 1.0){ // 有几何才算反弹。
			vec4 data3 = texelFetch(colortex3, texel, 0); // 读法线光照图。
			vec3 currNormal = DecodeNormal(data3.xy); // 解出本帧法线。
			vec3 currViewPos = ViewPos_From_ScreenPos_Raw(coord, currDepth); // 还原视空间位置。
			#ifdef DISTANT_HORIZONS // 远景像素用远景还原。
				if (isDH) currViewPos = ViewPos_From_ScreenPos_Raw_DH(coord, currDepth); // 远景还原。
			#endif
			vec3 gi = vec3(0.0); // 本帧反弹。
			#if MC_VERSION >= 11605 // 新版本按天光标记决定是否反弹。
				#if defined OMNI_SUNLIGHT_LEAK_FIX && !defined OMNI_END // 主世界做泄漏修正。
					if (data3.w > 0.0 || isEyeInWater == 1) // 只有接到天光或在水里。
				#endif
					gi = RSM(currViewPos, currNormal); // 算一次反弹。
			#else // 旧版本还要求像素足够远。
				#if defined OMNI_SUNLIGHT_LEAK_FIX && !defined OMNI_END // 主世界做泄漏修正。
					if (currDepth > 0.7 && (data3.w > 0.0 || isEyeInWater == 1)) // 较远且接到天光。
				#else // 末地或关闭修正。
					if (currDepth > 0.7) // 只要求较远。
				#endif
					gi = RSM(currViewPos, currNormal); // 算一次反弹。
			#endif
			#ifdef DISTANT_HORIZONS // 手机上算屏幕位移。
				vec2 velocity = CalculateCameraVelocity(coord, currDepth, isDH); // 远景版位移。
			#else // 近景版位移。
				vec2 velocity = CalculateCameraVelocity(coord, currDepth); // 近景版位移。
			#endif
			vec2 pcoord = coord - velocity; // 映射到上一帧坐标。
			vec2 prevCoord = clamp(pcoord, vec2(0.0), vec2(1.0) - pixelSize * 2.0); // 夹到画面内。
			if (prevCoord == pcoord){ // 历史坐标有效才做滤波。
				prevCoord = prevCoord * OMNI_GI_RENDER_RESOLUTION * screenSize - 0.5; // 换成历史纹素坐标。
				vec2 prevTexel = floor(prevCoord); // 历史纹素整数部分。
				vec3 prevGi = vec3(0.0); // 累积的历史反弹。
				float weights = 0.0; // 权重和。
				for(float i = 0.0; i <= 1.0; i++){ // 四个历史像素双向插值。
				for(float j = 0.0; j <= 1.0; j++){ // 纵方向。
					vec2 sampleTexelcoord = prevTexel + vec2(i, j); // 历史纹素。
					vec4 prevData = texelFetch(colortex2, ivec2(sampleTexelcoord.x + OMNI_GI_RENDER_RESOLUTION * screenSize.x, sampleTexelcoord.y), 0); // 读历史法线深度。
					vec3 prevNormal = prevData.xyz * 2.0 - 1.0; // 还原历史法线。
					float normalWeight = float(dot(currNormal, prevNormal) > 0.5); // 法线相近才参与。
					float currDist = -currViewPos.z; // 本帧到相机的距离。
					currDist = min(currDist, 1000.0); // 限长避免远处权重异常。
					float prevDist = prevData.a * 1000.0; // 历史距离。
					vec3 cameraVelocity = mat3(gbufferModelView) * (cameraPosition - previousCameraPosition); // 相机速度转到视空间。
					float depthWeight = max(abs(currDist - prevDist - cameraVelocity.z), 0.0); // 距离差。
					depthWeight = exp(-depthWeight / (currDist * 0.1 + 0.1)); // 差距越大权重越低。
					depthWeight = saturate(depthWeight * 2.0); // 放大后再收敛。
					float bilinearWeight = (1.0 - abs(prevCoord.x - sampleTexelcoord.x)) * (1.0 - abs(prevCoord.y - sampleTexelcoord.y)); // 双线性权重。
					bilinearWeight *= normalWeight * depthWeight; // 总权重。
					prevGi += CurveToLinear(texelFetch(colortex2, ivec2(sampleTexelcoord), 0).rgb) * bilinearWeight; // 累加解码后的历史反弹。
					weights += bilinearWeight; // 累加权重。
				}}
				gi = mix(gi, prevGi, 0.95 * weights); // 与历史混合。
			}
			prev = vec4(LinearToCurve(gi), 0.0); // 编码回历史格式。
		}
	}
	coord.x -= 1.0; // 顶行左侧一格存法线与距离。
	if (saturate(coord) == coord){ // 只在有效范围内处理。
		ivec2 texel = ivec2(floor(coord * screenSize)); // 对应的屏幕纹素。
		float depth = texelFetch(depthtex1, texel, 0).x; // 不透明深度。
		#ifdef DISTANT_HORIZONS // 远景处理。
			bool isDH = false; // 远景标记。
			if (depth == 1.0){ // 天空像素。
				depth = texelFetch(dhDepthTex0, texel, 0).x; // 改读远景深度。
				isDH = true; // 标记远景。
			}
		#endif
		if (depth < 1.0){ // 有几何才写历史数据。
			vec3 normal = DecodeNormal(texelFetch(colortex3, texel, 0).xy); // 解法线。
			float dist = LinearDepth_From_ScreenDepth(depth); // 深度换米制距离。
			#ifdef DISTANT_HORIZONS // 远景像素用远景换算。
				if(isDH) dist = LinearDepth_From_ScreenDepth_DH(depth); // 远景换算。
			#endif
			prev = vec4(normal * 0.5 + 0.5, dist * 0.001); // 法线压到零到一，距离缩小存进透明通道。
		}else{ // 天空像素没有有效历史。
			prev = vec4(vec3(0.5), 0.0); // 写入中性值。
		}
	}
	return prev; // 返回本帧要写回二号画面的数据。
}
#endif // 延迟一号结束。
////////////////////END_IF//////////////////////////////////////////////////////////////////////////
////////////////////PROGRAM_GI_1////////////////////////////////////////////////////////////////////
////////////////////PROGRAM_GI_1////////////////////////////////////////////////////////////////////
#if (defined OMNI_DEFERRED2_PASS && !defined OMNI_END) || (defined OMNI_END && defined OMNI_DEFERRED4_PASS) // 主世界在延迟二号、末地在延迟四号做全局光空间滤波。
// 全局光空间滤波：在七乘七邻域里按法线与深度加权平均，抑制半分辨率带来的噪点。
vec3 GI_SpatialFilter(float dist, vec3 normal, vec3 viewDir){
	const vec2 offset[49] = vec2[49]( // 七乘七邻域偏移表。
	vec2(-3.0, -3.0), vec2(-2.0, -3.0), vec2(-1.0, -3.0), vec2(0.0, -3.0), vec2(1.0, -3.0), vec2(2.0, -3.0), vec2(3.0, -3.0),
	vec2(-3.0, -2.0), vec2(-2.0, -2.0), vec2(-1.0, -2.0), vec2(0.0, -2.0), vec2(1.0, -2.0), vec2(2.0, -2.0), vec2(3.0, -2.0),
	vec2(-3.0, -1.0), vec2(-2.0, -1.0), vec2(-1.0, -1.0), vec2(0.0, -1.0), vec2(1.0, -1.0), vec2(2.0, -1.0), vec2(3.0, -1.0),
	vec2(-3.0,  0.0), vec2(-2.0,  0.0), vec2(-1.0,  0.0), vec2(0.0,  0.0), vec2(1.0,  0.0), vec2(2.0,  0.0), vec2(3.0,  0.0),
	vec2(-3.0,  1.0), vec2(-2.0,  1.0), vec2(-1.0,  1.0), vec2(0.0,  1.0), vec2(1.0,  1.0), vec2(2.0,  1.0), vec2(3.0,  1.0),
	vec2(-3.0,  2.0), vec2(-2.0,  2.0), vec2(-1.0,  2.0), vec2(0.0,  2.0), vec2(1.0,  2.0), vec2(2.0,  2.0), vec2(3.0,  2.0),
	vec2(-3.0,  3.0), vec2(-2.0,  3.0), vec2(-1.0,  3.0), vec2(0.0,  3.0), vec2(1.0,  3.0), vec2(2.0,  3.0), vec2(3.0,  3.0));
	vec2 coord = texCoord * OMNI_GI_RENDER_RESOLUTION; // 全局光分辨率下的坐标。
	float weights = 0.0; // 权重和。
	vec3 gi = vec3(0.0); // 累积的反弹颜色。
	float clampedDist = min(dist, 1000.0); // 距离限长。
	float b = clampedDist * 0.001 + 0.025; // 深度阈值里的中间量。
	float depthThreshold = min(0.1 + clampedDist * 0.05, 1.1) + saturate(1.0 - abs(dot(normal, viewDir)) / b) * 10.0; // 掠射角放宽深度阈值。
	vec2 border = vec2(OMNI_GI_RENDER_RESOLUTION) - pixelSize * 2.0; // 边界。
	vec2 offsetScale = pixelSize * 4.0 * OMNI_GI_RENDER_RESOLUTION; // 邻域步长。
	for (int i = 0; i < 49; i++){ // 遍历四十九个邻点。
		vec2 sampleCoord = coord + offset[i] * offsetScale; // 采样坐标。
		sampleCoord = clamp(sampleCoord, vec2(0.0), border); // 夹到有效范围。
		float weight = length(offset[i]); // 按到中心的距离算权重。
	  	weight = exp2(-weight * weight * 0.1); // 高斯权重。
		vec4 sampleData = textureLod(colortex2, sampleCoord + vec2(OMNI_GI_RENDER_RESOLUTION, 0.0), 0.0); // 读历史法线深度。
		vec3 sampleNormal = sampleData.xyz * 2.0 - 1.0; // 还原法线。
		float normalWeight = abs(dot(normal, sampleNormal)); // 法线相近度。
		normalWeight = pow(normalWeight, 64.0); // 高次方只保留很接近的。
		float depthWeight = saturate(-abs(sampleData.w * 1000.0 - clampedDist) + depthThreshold); // 深度相近度。
		weight = weight * normalWeight * depthWeight + 1e-20; // 总权重，加极小值避免全零。
		gi += CurveToLinear(textureLod(colortex2, sampleCoord, 0.0).rgb) * weight; // 累加解码后的反弹。
		weights += weight; // 累加权重。
	}
	gi /= weights; // 平均。
	return LinearToCurve(gi); // 编码后返回。
}
#endif // 延迟二号结束。
////////////////////END_IF//////////////////////////////////////////////////////////////////////////
#endif // 全局光结束。
// 地平线遮蔽：沿视线做多切片搜索最大地平线角，积分出半球被挡住的比重。
// 调用前提：`texCoord`、`gbufferProjection`、`depthtex1` 已声明。
float GroundTruthBasedAmbientOcclusion(vec3 viewPos, vec3 viewDir, vec3 normal){
	#ifdef OMNI_TAA // 开时间抗锯齿时用逐帧噪声。
		vec2 noise = BlueNoiseTemporal(); // 每帧变化的蓝噪声。
	#else // 否则用空间噪声。
		vec2 noise = BlueNoise(); // 固定空间噪声。
	#endif
	const float steps = OMNI_GTAO_QUALITY; // 环绕视线的切片数。
	const float rSteps = 1.0 / steps; // 切片数倒数。
	const float sliceSteps = OMNI_GTAO_SLICE_QUALITY; // 每个切片的搜索步数。
	const float rSliceSteps = 1.0 / sliceSteps; // 步数倒数。
	const float falloffStart = OMNI_GTAO_FALLOFF_START; // 衰减起点。
	const float maxSampleRadius = OMNI_GTAO_MAX_RADIUS; // 屏幕半径上限。
	#ifdef GTAO_FALLOFF_Z_OFFSET // 可选的深度加权开关。
		const float falloffZoffset = 1.7; // 深度方向放大系数。
	#endif
	float projFactor = 0.125 * gbufferProjection[1][1]; // 投影缩放系数。
	#if OMNI_GTAO_RADIUS_MODE == 0 // 世界半径模式。
		#ifdef DISTANT_HORIZONS // 有远景时衰减更慢。
			float radius = OMNI_GTAO_WORLD_RADIUS - viewPos.z * 0.02; // 世界半径随距离缩小。
		#else // 没有远景时衰减更快。
			float radius = OMNI_GTAO_WORLD_RADIUS - viewPos.z * 0.01; // 世界半径随距离缩小。
		#endif
		float sampleRadiusRaw = radius * projFactor / -viewPos.z; // 换成屏幕半径。
		float sampleRadius = min(sampleRadiusRaw, maxSampleRadius); // 上限。
		float falloff = sampleRadius * radius / sampleRadiusRaw; // 衰减距离。
	#else // 屏幕半径模式。
		const float sampleRadius = OMNI_GTAO_SCREEN_RADIUS; // 固定屏幕半径。
		float falloff = sampleRadius / projFactor * -viewPos.z; // 换算成世界衰减距离。
	#endif
	float ao = 0.0; // 累积的遮蔽。
	for (float i = 0.0; i < steps; i++){ // 逐切片。
		float sliceAngle = (i + noise.x) * rSteps * PI; // 切片角度，只扫半圈因为两侧对称。
		vec3 sliceDir = vec3(cos(sliceAngle), sin(sliceAngle), 0.0); // 切片方向。
		vec3 orthoSliceDir = sliceDir - dot(sliceDir, viewDir) * viewDir; // 切片方向正交到视线的分量。
		vec3 axis = cross(sliceDir, viewDir); // 切片平面法向。
		vec3 projNormal = normal - dot(normal, axis) * axis; // 法线投影到切片平面。
		float rProjNormalLength = inversesqrt(dot(projNormal, projNormal)); // 投影长度倒数。
		float cosNormalAngle = saturate(dot(projNormal, viewDir) * rProjNormalLength); // 投影法线与视线夹角余弦。
		float normalAngle = sign(dot(orthoSliceDir, projNormal)) * facos(cosNormalAngle); // 带符号的法线角。
		vec2 minCosHorizonAngle = cos(vec2(normalAngle + hPI, normalAngle - hPI)); // 两侧地平线角的下限。
		vec2 maxCosHorizonAngle = minCosHorizonAngle; // 两侧可见地平线角的初值。
		for (float j = 0.0; j < sliceSteps; j++){ // 逐搜索步。
			float stepNoise = (i + j * sliceSteps) * 0.61803399; // 用黄金比错开各步。
			stepNoise = fract(stepNoise + noise.y); // 加噪声后取小数。
			float offset = (j + stepNoise) * rSliceSteps; // 归一化搜索距离。
			offset *= offset; // 平方让近处更密。
			vec2 sampleOffset = offset * sliceDir.xy * sampleRadius; // 屏幕偏移。
			sampleOffset.y *= aspectRatio; // 修正宽高比。
			{ // 正向搜索。
				vec2 sampleCoord = texCoord + sampleOffset; // 正向采样坐标。
				float sampleDepth = textureLod(depthtex1, sampleCoord, 0.0).x; // 采样深度。
				#ifdef DISTANT_HORIZONS // 远景处理。
					vec3 sampleVector = vec3(0.0); // 采样向量。
					if (sampleDepth == 1.0){ // 天空像素改读远景深度。
						sampleDepth = textureLod(dhDepthTex0, sampleCoord, 0.0).x; // 远景深度。
						sampleVector = ViewPos_From_ScreenPos_DH(sampleCoord, sampleDepth); // 远景还原。
					}else{ // 近景像素正常还原。
						sampleVector = ViewPos_From_ScreenPos(sampleCoord, sampleDepth); // 近景还原。
					}
					sampleVector = sampleVector - viewPos; // 换成相对当前点。
				#else // 没有远景时直接还原。
					vec3 sampleVector = ViewPos_From_ScreenPos(sampleCoord, sampleDepth) - viewPos; // 采样点相对当前点。
				#endif
				float rSampleDist = inversesqrt(dot(sampleVector, sampleVector)); // 距离倒数。
				float cosHorizonAngle = dot(sampleVector, viewDir) * rSampleDist; // 采样点给出的地平线余弦。
				#ifdef GTAO_FALLOFF_Z_OFFSET // 可选的深度加权。
					float offsetDist = length(vec3(sampleVector.xy, sampleVector.z * falloffZoffset)); // 加权距离。
					float falloffWeight = remapSaturate(offsetDist, falloff * falloffStart, falloff); // 衰减权重。
				#else // 默认按距离加权。
					float falloffWeight = remapSaturate(1.0 / rSampleDist, falloff * falloffStart, falloff); // 衰减权重。
				#endif
				cosHorizonAngle = mix(cosHorizonAngle, minCosHorizonAngle.x, falloffWeight); // 远处回落到下限。
				maxCosHorizonAngle.x = max(cosHorizonAngle, maxCosHorizonAngle.x); // 取可见地平线角。
			}{ // 反向搜索。
				vec2 sampleCoord = texCoord - sampleOffset; // 反向采样坐标。
				float sampleDepth = textureLod(depthtex1, sampleCoord, 0.0).x; // 采样深度。
				#ifdef DISTANT_HORIZONS // 远景处理。
					vec3 sampleVector = vec3(0.0); // 采样向量。
					if (sampleDepth == 1.0){ // 天空像素改读远景深度。
						sampleDepth = textureLod(dhDepthTex0, sampleCoord, 0.0).x; // 远景深度。
						sampleVector = ViewPos_From_ScreenPos_DH(sampleCoord, sampleDepth); // 远景还原。
					}else{ // 近景像素正常还原。
						sampleVector = ViewPos_From_ScreenPos(sampleCoord, sampleDepth); // 近景还原。
					}
					sampleVector = sampleVector - viewPos; // 换成相对当前点。
				#else // 没有远景时直接还原。
					vec3 sampleVector = ViewPos_From_ScreenPos(sampleCoord, sampleDepth) - viewPos; // 采样点相对当前点。
				#endif
				float rSampleDist = inversesqrt(dot(sampleVector, sampleVector)); // 距离倒数。
				float cosHorizonAngle = dot(sampleVector, viewDir) * rSampleDist; // 采样点给出的地平线余弦。
				#ifdef GTAO_FALLOFF_Z_OFFSET // 可选的深度加权。
					float offsetDist = length(vec3(sampleVector.xy, sampleVector.z * falloffZoffset)); // 加权距离。
					float falloffWeight = remapSaturate(offsetDist, falloff * falloffStart, falloff); // 衰减权重。
				#else // 默认按距离加权。
					float falloffWeight = remapSaturate(1.0 / rSampleDist, falloff * falloffStart, falloff); // 衰减权重。
				#endif
				cosHorizonAngle = mix(cosHorizonAngle, minCosHorizonAngle.y, falloffWeight); // 远处回落到下限。
				maxCosHorizonAngle.y = max(cosHorizonAngle, maxCosHorizonAngle.y); // 取可见地平线角。
			}
		}
		maxCosHorizonAngle = vec2(-facos(maxCosHorizonAngle.y), facos(maxCosHorizonAngle.x)) * 2.0; // 两侧换成开口角。
		float horizonAngleIntegra = 2.0 * cosNormalAngle + (maxCosHorizonAngle.x + maxCosHorizonAngle.y) * sin(normalAngle) - cos(maxCosHorizonAngle.x - normalAngle) - cos(maxCosHorizonAngle.y - normalAngle); // 这一片的半球可见缺口。
		ao += horizonAngleIntegra / rProjNormalLength; // 累加。
	}
	ao *= 0.25 * rSteps; // 平均。
	return saturate(mix(1.0, ao, OMNI_GTAO_STRENGTH)); // 按强度在无遮蔽与遮蔽之间插值。
}
// 遮蔽多弹射：按表面底色给遮蔽补一层间接光，深色表面补得少，避免暗部压死。
vec3 GTAOMultiBounce(float ao, vec3 albedo){
	vec3 a =  2.0404 * albedo - 0.3324; // 一次项拟合系数。
	vec3 b = -4.7951 * albedo + 0.6417; // 二次项拟合系数。
	vec3 c =  2.7552 * albedo + 0.6903; // 三次项拟合系数。
	return max(vec3(ao), ((ao * a + b) * ao + c) * ao); // 取多项式与原始遮蔽的较大值。
}
#endif // 文件守卫结束。
