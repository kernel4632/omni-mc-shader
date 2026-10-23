/*
手持光源：火把球形光与手电筒一束光，含光斑形状、屏幕空间阴影与表面高光。
来源 iterationT `Lib/BasicFounctions/Blocklight.glsl` 的手持光段与手电筒段。
调用位置：由 `effects/lighting/blocklight.glsl` 引入；地形、实体、手等光照阶段调用 `HeldLighting`、`TorchSpecularHighlight`。
可复制示例：
    `vec3 held = HeldLighting(viewPos, viewDir, normal, roughness, ao, isHand);`
    `TorchSpecularHighlight(color, viewPos, viewDir, dist, albedo, roughness, isHand);`
设计原因与取舍：手持光与方块光、纹理自发光互不相干，拆到这里按“手持光源”这一主体阅读；
    手电筒模式与火把模式的分支、指针平滑、阴影品质都照 iterationT 原样。
*/
#ifndef OMNI_HELD_LIGHT_INCLUDED
#define OMNI_HELD_LIGHT_INCLUDED // 置上标记，后续再次引用直接跳过。
// 屏幕空间阴影的步进循环在通用库。
#include "/gfx/shadow.glsl"
// --- 手电筒光斑形状：按光线与指向的夹角给出一束光的强度分布 ---
// 为什么用曲线两次叠加：主瓣给中心亮区，副瓣给一点点外圈余晖；再乘一圈环形暗环，让光斑边界更像手电筒。
float spotShape(float r){
	float shape = curve(saturate(r * 2.0 - (2.0 - OMNI_FLASHLIGHT_FOV))); // 中心主瓣，夹角越小越亮。
	shape += curve(saturate(r * 1.25 - (1.0 - OMNI_FLASHLIGHT_FOV))) * 0.01; // 很弱的外圈余晖。

	const float ringSize = 8.0 / OMNI_FLASHLIGHT_FOV; // 暗环的宽度随光束角度缩放。
	shape *= 1.0 - curve(saturate(1.0 - abs(r * ringSize - ringSize + 1.0))) * 0.25; // 在主瓣外面压一圈暗环。

	return shape; // 返回零到一的光斑强度。
}

// --- 手持光源的屏幕空间阴影：在屏幕里沿光源方向找遮挡 ---
// 输入是视空间表面位置、视线方向、法线与光源方向；输出可见度，零到一。
// 为什么起点要沿法线抬一点：手持光源离表面很近，不抬会刚出发就打到自己，整片出现自阴影。
// 为什么用蓝噪声抖动采样：固定采样会在光斑边缘留下规则条纹，抖动后配合时间抗锯齿消除。
// 步进主循环在 `gfx/shadow.glsl`，本函数只选步数、深度图与抖动。
float TorchScreenSpaceShadow(vec3 viewPos, vec3 viewDir, vec3 normal, vec3 shadowDir){
	#if OMNI_HELDLIGHT_SHADOW_QUALITY > 0 // 高质量用两倍步数，阴影更连续、远处也压得住。
		const int omniHeldShadowSteps = 16;
	#else
		const int omniHeldShadowSteps = 8; // 低质量步数与原来一致。
	#endif

	#ifdef OMNI_TAA // 打开时间抗锯齿时用逐帧抖动，抗锯齿会把噪点平均掉。
		float noise = BlueNoiseTemporal().x; // 每帧变化的蓝噪声。
		vec2 offsetCoord = 0.5 + taaJitter * 0.5; // 采样坐标补上本帧抖动。
	#else // 不开时间抗锯齿时只能固定噪声。
		float noise = BlueNoise().x; // 按像素平铺的固定噪声。
		vec2 offsetCoord = vec2(0.5); // 不补抖动。
	#endif

	#ifdef DISTANT_HORIZONS // 有远景时，近景是天空才改用远景深度。
		return gfx_screen_space_shadow(viewPos, viewDir, normal, shadowDir, depthtex1, dhDepthTex1, gbufferProjection, gbufferProjectionInverse,
			dhProjectionInverse, max(pixelSize.x, pixelSize.y), offsetCoord, noise, true, omniHeldShadowSteps, OMNI_HELDLIGHT_SHADOW_STRENGTH); // 一次调用完成屏幕步进。
	#else
		return gfx_screen_space_shadow(viewPos, viewDir, normal, shadowDir, depthtex1, depthtex1, gbufferProjection, gbufferProjectionInverse,
			gbufferProjectionInverse, max(pixelSize.x, pixelSize.y), offsetCoord, noise, false, omniHeldShadowSteps, OMNI_HELDLIGHT_SHADOW_STRENGTH); // 没有远景时用近景深度占位。
	#endif
}

// 手电筒指向：打开相机平滑时按两个平滑角度滞后于视角，否则始终朝相机正前方。
// 为什么单独成函数：光照与高光两处要同一个方向，分开写容易在改动时只改到一处。
vec3 FlashlightAimDirection(){
	#if OMNI_FLASHLIGHT_CAMERA_SMOOTH // 打开指向平滑时，光束方向滞后于视角。
		float angleRx = eyeRxSmooth * -OMNI_FLASHLIGHT_CAMERA_SMOOTH_TIME; // 俯仰角按过渡时长滞后。
		mat3 Rx = mat3(1.0,  0.0,          0.0,
					   0.0,  cos(angleRx), sin(angleRx),
					   0.0, -sin(angleRx), cos(angleRx)); // 俯仰旋转矩阵。
		float angleRy = eyeRySmooth * -OMNI_FLASHLIGHT_CAMERA_SMOOTH_TIME; // 偏航角按过渡时长滞后。
		mat3 Ry = mat3(cos(angleRy), 0.0, -sin(angleRy),
					   0.0,          1.0,  0.0,
					   sin(angleRy), 0.0,  cos(angleRy)); // 偏航旋转矩阵。
		return Ry * Rx * vec3(0.0, 0.0, -1.0); // 平滑后的光束指向。
	#else
		return vec3(0.0, 0.0, -1.0); // 不平滑时始终朝相机正前方。
	#endif
}

// --- 手持光源：火把球形光与手电筒一束光 ---
// 输入是视空间表面位置、视线方向、法线、粗糙度、遮蔽项与是否手部；输出该像素收到的手持光颜色。
// 为什么手部单独处理：手持物离光源最近，直接用发光等级当亮度，不再做方向与衰减，避免手被自己的光源照出条纹。
vec3 HeldLighting(vec3 viewPos, vec3 viewDir, vec3 normal, float roughness, vec3 ao, bool isHand){
	float heldLightFalloff = 0.0; // 手持光累计衰减量。

	#if OMNI_HELDLIGHT_MODE > 0 // 手电筒模式：两支灯源各是一束朝前的光。

		if (isHand){ // 手部直接按发光等级给亮度。
			heldLightFalloff = 0.01 * max(heldBlockLightValue, heldBlockLightValue2); // 取两只手里较大的发光等级。
		}else{
			vec3 aimDir = FlashlightAimDirection(); // 光照与高光共用同一套指向。

			if (heldBlockLightValue > 0.0){ // 右手灯源。
				vec3 spotPosR = viewPos - vec3(OMNI_FLASHLIGHT_POS_R_X, OMNI_FLASHLIGHT_POS_R_Y, 0.0); // 灯源到表面的矢量。
				float spotDistR = length(spotPosR); // 灯源到表面的距离。
				vec3 shadowDirR = spotPosR / spotDistR; // 灯源指向表面的方向。

				float spotR = pow(max(spotDistR, 0.6), -OMNI_FLASHLIGHT_HELDLIGHT_FALLOFF); // 按距离衰减，最近不少于零点六米。
				spotR *= spotShape(dot(shadowDirR, aimDir)); // 乘光斑形状，只有落在光束里才亮。

				#ifdef OMNI_HELDLIGHT_SHADOW // 打开手持光阴影时投屏幕空间阴影。
					spotR *= TorchScreenSpaceShadow(viewPos, viewDir, normal, -shadowDirR); // 光源朝表面的反方向投射线。
				#endif
				spotR *= Fd_Burley(normal, -viewDir, -shadowDirR, roughness) * 1.7 + 0.05; // 乘漫反射，读图更自然。

				heldLightFalloff += heldBlockLightValue * spotR; // 按发光等级累加。
			}

			if (heldBlockLightValue2 > 0.0){ // 左手灯源，逻辑与右手同。
				vec3 spotPosL = viewPos - vec3(OMNI_FLASHLIGHT_POS_L_X, OMNI_FLASHLIGHT_POS_L_Y, 0.0); // 灯源到表面的矢量。
				float spotDistL = length(spotPosL); // 灯源到表面的距离。
				vec3 shadowDirL = spotPosL / spotDistL; // 灯源指向表面的方向。

				float spotL = pow(max(spotDistL, 0.6), -OMNI_FLASHLIGHT_HELDLIGHT_FALLOFF); // 按距离衰减，最近不少于零点六米。
				spotL *= spotShape(dot(shadowDirL, aimDir)); // 乘光斑形状，只有落在光束里才亮。

				#ifdef OMNI_HELDLIGHT_SHADOW
					spotL *= TorchScreenSpaceShadow(viewPos, viewDir, normal, -shadowDirL); // 光源朝表面的反方向投射线。
				#endif
				spotL *= Fd_Burley(normal, -viewDir, -shadowDirL, roughness) * 1.7 + 0.05; // 乘漫反射，读图更自然。

				heldLightFalloff += heldBlockLightValue2 * spotL; // 按发光等级累加。
			}
		}

		#ifdef OMNI_OVERWORLD // 主世界与下界末地用不同的亮度常数。
			return vec3(OMNI_FLASHLIGHT_COLOR_R, OMNI_FLASHLIGHT_COLOR_G, OMNI_FLASHLIGHT_COLOR_B) * (ao * 0.5 + 0.5) * (heldLightFalloff * (OMNI_HELDLIGHT_BRIGHTNESS * 0.02)); // 手电筒颜色乘遮蔽与强度。
		#else
			return vec3(OMNI_FLASHLIGHT_COLOR_R, OMNI_FLASHLIGHT_COLOR_G, OMNI_FLASHLIGHT_COLOR_B) * (ao * 0.5 + 0.5) * (heldLightFalloff * (OMNI_HELDLIGHT_BRIGHTNESS * 0.2)); // 下界末地常数放大十倍。
		#endif

	#else // 火把模式：一支从玩家位置向四周发散的球形光。

		if (isHand){ // 手部直接按发光等级给亮度。
			heldLightFalloff = 0.2 * max(heldBlockLightValue, heldBlockLightValue2); // 取两只手里较大的发光等级。
		}else{
			#ifdef OMNI_HELDLIGHT_SHADOW // 打开手持光阴影时分别给两只手投屏幕空间阴影。

				if (heldBlockLightValue > 0.0){ // 右手灯源。
					vec3 torchPosR = viewPos - vec3(OMNI_FLASHLIGHT_POS_R_X, OMNI_FLASHLIGHT_POS_R_Y, 0.0); // 灯源到表面的矢量。
					float torchDistR = length(torchPosR); // 灯源到表面的距离。
					torchDistR += 4.0 / (torchDistR + 2.0); // 近距离补一点距离，衰减曲线更圆润。

					float torchR = pow(torchDistR, -OMNI_HELDLIGHT_FALLOFF); // 按距离衰减。

					vec3 shadowDirR = -normalize(viewPos - vec3(OMNI_FLASHLIGHT_POS_R_X, OMNI_FLASHLIGHT_POS_R_Y, 0.0)); // 光源方向指向灯源。
					torchR *= TorchScreenSpaceShadow(viewPos, viewDir, normal, shadowDirR); // 投屏幕空间阴影。
					torchR *= Fd_Burley(normal, -viewDir, shadowDirR, roughness) * 1.7 + 0.05; // 乘漫反射。

					heldLightFalloff += heldBlockLightValue * torchR; // 按发光等级累加。
				}

				if (heldBlockLightValue2 > 0.0){ // 左手灯源，逻辑与右手同。
					vec3 torchPosL = viewPos - vec3(OMNI_FLASHLIGHT_POS_L_X, OMNI_FLASHLIGHT_POS_L_Y, 0.0); // 灯源到表面的矢量。
					float torchDistL = length(torchPosL); // 灯源到表面的距离。
					torchDistL += 4.0 / (torchDistL + 2.0); // 近距离补一点距离，衰减曲线更圆润。

					float torchL = pow(torchDistL, -OMNI_HELDLIGHT_FALLOFF); // 按距离衰减。

					vec3 shadowDirL = -normalize(viewPos - vec3(OMNI_FLASHLIGHT_POS_L_X, OMNI_FLASHLIGHT_POS_L_Y, 0.0)); // 光源方向指向灯源。
					torchL *= TorchScreenSpaceShadow(viewPos, viewDir, normal, shadowDirL); // 投屏幕空间阴影。
					torchL *= Fd_Burley(normal, -viewDir, shadowDirL, roughness) * 1.7 + 0.05; // 乘漫反射。

					heldLightFalloff += heldBlockLightValue2 * torchL; // 按发光等级累加。
				}

			#else // 不投阴影时两支灯源合成一支居中光源，省两次屏幕步进。

				float torchDist = length(viewPos); // 表面到相机的距离，当作到光源的距离。
				torchDist += 4.0 / (torchDist + 2.0); // 近距离补一点距离。
				heldLightFalloff = pow(torchDist, -OMNI_HELDLIGHT_FALLOFF); // 按距离衰减。
				heldLightFalloff *= Fd_Burley(normal, -viewDir, -viewDir, roughness) + 0.3; // 乘一个近似漫反射。

				heldLightFalloff *= heldBlockLightValue + heldBlockLightValue2; // 按两只手的发光等级之和累加。
			#endif
		}

		#ifdef OMNI_OVERWORLD // 主世界与下界末地用不同的亮度常数。
			return colorTorchlight * (ao * 0.5 + 0.5) * (heldLightFalloff * (OMNI_TORCHLIGHT_BRIGHTNESS * OMNI_HELDLIGHT_BRIGHTNESS * 0.0015)); // 火把光色乘遮蔽与强度。
		#else
			return colorTorchlight * (ao * 0.5 + 0.5) * (heldLightFalloff * (OMNI_TORCHLIGHT_BRIGHTNESS * OMNI_HELDLIGHT_BRIGHTNESS * 0.015)); // 下界末地常数放大十倍。
		#endif

	#endif
}

// --- 手持高光：把手持光源映到表面高光上 ---
// 输入是待修改的颜色、视空间位置、视线方向、距离、底色、法线与材质；就地把高光加到颜色里。
// 为什么手电筒与火把分开：手电筒用光斑形状限制高光范围，火把是接住相机方向的镜面反射，两者模型不同。
void TorchSpecularHighlight(inout vec3 color, vec3 viewPos, vec3 viewDir, float dist, vec3 albedo, vec3 normal, Material material){
	material.roughness = max(material.roughness, 0.002); // 粗糙度给一个下限，避免高光被压成无限细的线。
	#if OMNI_HELDLIGHT_MODE > 0 // 手电筒模式：高光只落在光束里。
		vec3 aimDir = FlashlightAimDirection(); // 与手持光共用同一套指向。

		float heldHighlight = 0.0; // 高光累计量。

		if (heldBlockLightValue > 0.0){ // 右手灯源。
			vec3 spotPosR = viewPos - vec3(OMNI_FLASHLIGHT_POS_R_X, OMNI_FLASHLIGHT_POS_R_Y, 0.0); // 灯源到表面的矢量。
			float spotDistR = length(spotPosR); // 灯源到表面的距离。
			vec3 shadowDirR = spotPosR / spotDistR; // 灯源指向表面的方向。

			float spotR = pow(max(spotDistR, 0.6), -OMNI_FLASHLIGHT_HELDLIGHT_FALLOFF); // 按距离衰减。
			spotR *= spotShape(dot(shadowDirR, aimDir)); // 只有落在光束里才亮。

			spotR *= SpecularGGX(normal, -viewDir, -shadowDirR, material.roughness, material.f0); // 乘 GGX 高光。

			heldHighlight += heldBlockLightValue * spotR; // 按发光等级累加。
		}

		if (heldBlockLightValue2 > 0.0){ // 左手灯源，逻辑与右手同。
			vec3 spotPosL = viewPos - vec3(OMNI_FLASHLIGHT_POS_L_X, OMNI_FLASHLIGHT_POS_L_Y, 0.0); // 灯源到表面的矢量。
			float spotDistL = length(spotPosL); // 灯源到表面的距离。
			vec3 shadowDirL = spotPosL / spotDistL; // 灯源指向表面的方向。

			float spotL = pow(max(spotDistL, 0.6), -OMNI_FLASHLIGHT_HELDLIGHT_FALLOFF); // 按距离衰减。
			spotL *= spotShape(dot(shadowDirL, aimDir)); // 只有落在光束里才亮。

			spotL *= SpecularGGX(normal, -viewDir, -shadowDirL, material.roughness, material.f0); // 乘 GGX 高光。

			heldHighlight += heldBlockLightValue2 * spotL; // 按发光等级累加。
		}

		if (heldHighlight > 0.001){ // 高光太小就不改颜色，省一次加法。
			#ifdef OMNI_OVERWORLD
				color += vec3(OMNI_FLASHLIGHT_COLOR_R, OMNI_FLASHLIGHT_COLOR_G, OMNI_FLASHLIGHT_COLOR_B) * albedo * (heldHighlight * (OMNI_HELDLIGHT_BRIGHTNESS * 0.0025)); // 手电筒颜色乘底色与强度。
			#else
				color += vec3(OMNI_FLASHLIGHT_COLOR_R, OMNI_FLASHLIGHT_COLOR_G, OMNI_FLASHLIGHT_COLOR_B) * albedo * (heldHighlight * (OMNI_HELDLIGHT_BRIGHTNESS * 0.025)); // 下界末地常数放大十倍。
			#endif
		}
	#else // 火把模式：高光取相机方向上的镜面反射。
		float heldHighlight = SpecularGGX(normal, -viewDir, -viewDir, material.roughness, material.f0); // 光源方向近似取视线方向。

		if (heldHighlight > 0.001){ // 高光太小就不改颜色。
			dist += 4.0 / (dist + 2.0); // 近距离补一点距离。
			heldHighlight *= pow(dist, -OMNI_HELDLIGHT_FALLOFF); // 按距离衰减。

			heldHighlight *= (heldBlockLightValue + heldBlockLightValue2); // 按两只手的发光等级之和累加。

			#ifdef OMNI_OVERWORLD
				color += colorTorchlight * albedo * (heldHighlight * (OMNI_TORCHLIGHT_BRIGHTNESS * OMNI_HELDLIGHT_BRIGHTNESS * 0.0002)); // 火把光色乘底色与强度。
			#else
				color += colorTorchlight * albedo * (heldHighlight * (OMNI_TORCHLIGHT_BRIGHTNESS * OMNI_HELDLIGHT_BRIGHTNESS * 0.002)); // 下界末地常数放大十倍。
			#endif
		}
	#endif
}
#endif // 文件守卫结束。
