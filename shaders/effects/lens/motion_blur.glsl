/*
效果文件 `effects/lens/motion_blur.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/lens/motion_blur.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_MOTION_BLUR_INCLUDED
#define OMNI_MOTION_BLUR_INCLUDED
/*
相机动态模糊：按本像素相对上一帧的屏幕位移沿快门方向平均场景颜色。
来源 iterationT `MotionBlur.glsl`。
调用位置：由 `effects/lens/lens.glsl` 引入；程序主体 `MotionBlurSceneColor()` 在 `effects/lens/post_motionblur.glsl`，
    它调用这里的 `MotionBlur()`；相机速度 `MotionBlurCameraVelocity` 也被别处的重投影引用。
可复制示例：
    `vec3 blurred = MotionBlur();`
    `vec2 velocity = MotionBlurCameraVelocity(coord, depth);`
设计原因与取舍：模糊采样与相机速度是同一套位移计算，放一起；是否抖动的开关照 iterationT 原样。
*/
// 模糊取样循环放在通用后期库，本文件只判断哪些像素参与并传入位移。
#include "/gfx/post.glsl"
// 手部深度与玩家编号判断在绑定层，避免这里再写一份阈值。
#include "/bind/gbuffer.glsl"
// --- 相机动态模糊 ---
// 用上一帧相机把当前表面重投影回屏幕，沿两帧之间的屏幕位移取几个历史位置做平均，模拟快门时间内相机的移动。
// 为什么只做相机运动：没有实体速度缓冲，硬算会把静止物体也拖出鬼影，所以只处理相机移动造成的整屏位移。
// 无效情况（手、覆盖层、传送、越界）都提前返回，让这些像素保持清晰。
vec2 MotionBlurCameraVelocity(vec2 coord, float depth){
	vec3 projection = vec3(coord, depth) * 2.0 - 1.0; // 转负一到一。
	projection = (vec3(vec2(gbufferProjectionInverse[0].x, gbufferProjectionInverse[1].y) * projection.xy, 0.0) + gbufferProjectionInverse[3].xyz) / (gbufferProjectionInverse[2].w * projection.z + gbufferProjectionInverse[3].w); // 逆投影到视空间。
	if (bind_is_hand_depth(depth)){ // 手按固定深度偏移补偿相机位移。
		projection += (gbufferPreviousModelView[3].xyz - gbufferModelView[3].xyz) * MC_HAND_DEPTH; // 手的固定偏移。
	}else{ // 普通世界表面。
		projection = mat3(gbufferModelViewInverse) * projection + gbufferModelViewInverse[3].xyz; // 视空间转世界。
		if (depth < 1.0) projection += cameraPosition - previousCameraPosition; // 有限深度才补相机位移。
		projection = mat3(gbufferPreviousModelView) * projection + gbufferPreviousModelView[3].xyz; // 转到上一帧视空间。
	}
	projection = (vec3(gbufferPreviousProjection[0].x, gbufferPreviousProjection[1].y, gbufferPreviousProjection[2].z) * projection + gbufferPreviousProjection[3].xyz) / -projection.z * 0.5 + 0.5; // 投到上一帧屏幕。
	return coord - projection.xy; // 位移等于当前坐标减上一帧坐标。
}

// 相机动态模糊主入口：沿快门方向的中心位置取历史颜色，按质量选项决定样本数。
// 快门角决定拖影长度；抖动选项给采样位置加一点随机，减少采样不足产生的条纹。
vec3 MotionBlur(){
	float materialIDs = floor(texelFetch(colortex6, texelCoord, 0).b * 255.0); // 读当前像素的材质编号。
	float depth = 0.0; // 该像素用于重投影的深度。
	if (materialIDs == MATID_WATER || materialIDs == MATID_ICE){ // 水和冰用含半透明的深度。
		depth = texelFetch(depthtex0, texelCoord, 0).x; // 读零号深度。
	}else{ // 其他表面用不含半透明的深度。
		depth = texelFetch(depthtex1, texelCoord, 0).x; // 读一号深度。
	}
	vec2 velocity = vec2(0.0); // 屏幕位移，默认零。
	#ifdef OMNI_DISABLE_PLAYER_TAA_MOTION_BLUR // 关闭玩家动态模糊时玩家不参与。
		bool blurPixel = bind_is_world_depth(depth) && materialIDs != MATID_END_PORTAL && !bind_is_player_id(materialIDs); // 手与玩家都排除。
	#else // 默认只排除手和末地传送门。
		bool blurPixel = bind_is_world_depth(depth) && materialIDs != MATID_END_PORTAL; // 近处左手以外的世界表面参与。
	#endif
	if (blurPixel){ // 先用宏决定是否参与，再走一条完整的 `if`，避免判断括号被预处理指令切开。
		velocity = MotionBlurCameraVelocity(texCoord, depth); // 算屏幕位移。
	}
	#if OMNI_MOTION_BLUR_DITHER // 开启抖动时把开关交给通用库。
		bool dither = true; // 采样位置加交错梯度噪声。
	#else
		bool dither = false; // 不加抖动。
	#endif
	return gfx_motion_blur(colortex7, texCoord, texelCoord, gl_FragCoord.xy, velocity,
		OMNI_MOTION_BLUR_SHUTTER_ANGLE, int(OMNI_MOTION_BLUR_QUALITY), dither); // 取样循环在通用库里。
}

#endif // OMNI_MOTION_BLUR_INCLUDED
