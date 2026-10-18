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
#ifndef OMNI_MOTION_BLUR_INCLUDED
#define OMNI_MOTION_BLUR_INCLUDED // 置上标记，后续再次引用直接跳过。
// --- 相机动态模糊 ---
// 用上一帧相机把当前表面重投影回屏幕，沿两帧之间的屏幕位移取几个历史位置做平均，模拟快门时间内相机的移动。
// 为什么只做相机运动：没有实体速度缓冲，硬算会把静止物体也拖出鬼影，所以只处理相机移动造成的整屏位移。
// 无效情况（手、覆盖层、传送、越界）都提前返回，让这些像素保持清晰。
vec2 MotionBlurCameraVelocity(vec2 coord, float depth){
	vec3 projection = vec3(coord, depth) * 2.0 - 1.0; // 转负一到一。
	projection = (vec3(vec2(gbufferProjectionInverse[0].x, gbufferProjectionInverse[1].y) * projection.xy, 0.0) + gbufferProjectionInverse[3].xyz) / (gbufferProjectionInverse[2].w * projection.z + gbufferProjectionInverse[3].w); // 逆投影到视空间。
	if (depth < 0.7){ // 手按固定深度偏移补偿相机位移。
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
		bool blurPixel = depth > 0.7 && materialIDs != MATID_END_PORTAL && materialIDs != MATID_ENTITIES_PLAYER; // 手与玩家都排除。
	#else // 默认只排除手和末地传送门。
		bool blurPixel = depth > 0.7 && materialIDs != MATID_END_PORTAL; // 近处左手以外的世界表面参与。
	#endif
	if (blurPixel){ // 先用宏决定是否参与，再走一条完整的 `if`，避免判断括号被预处理指令切开。
		velocity = MotionBlurCameraVelocity(texCoord, depth); // 算屏幕位移。
	}
	vec3 color = vec3(0.0); // 输出颜色。
	if (length(velocity) < 5e-7){ // 位移极小说明相机没动，直接用历史颜色。
		color = CurveToLinear(texelFetch(colortex7, texelCoord, 0).rgb); // 读七号画面当前颜色。
	}else{ // 相机动了，沿位移方向平均。
		velocity *= OMNI_MOTION_BLUR_SHUTTER_ANGLE / 720.0; // 快门角换算成拖影长度。
		velocity = clamp(velocity, -0.1, 0.1); // 限制单帧拖影上限。
		float steps = OMNI_MOTION_BLUR_QUALITY; // 一侧的采样步数。
		float samples = 0.0; // 有效样本计数。
		float dither = 0.0; // 采样抖动。
		#if OMNI_MOTION_BLUR_DITHER // 开启抖动时给采样位置加噪声。
			dither = InterleavedGradientNoise(gl_FragCoord.xy); // 交错梯度噪声。
		#endif
		for (float i = -steps; i <= steps; i++){ // 沿快门方向对称取样。
			vec2 coord = texCoord.st + velocity / (steps + 1.0) * (i + dither); // 这个样本的坐标。
			if (saturate(coord) == coord){ // 坐标在画面内才采。
				color += CurveToLinear(textureLod(colortex7, coord, 0.0).rgb); // 累加历史颜色。
				samples++; // 计数。
			}
		}
		color.rgb /= samples; // 按有效样本数平均。
	}
	return color; // 返回模糊后的线性颜色。
}

#endif // 文件守卫结束。
