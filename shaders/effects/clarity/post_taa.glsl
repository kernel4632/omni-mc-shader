/*
后期时间抗锯齿历史：`composite7` 程序的算法体，把重投影后的颜色写进七号画面，供下一帧当历史。
职责：按选项排除手与玩家、算相机速度、做邻域裁剪重投影；下界额外把参考深度与当前深度打包进透明度通道。
调用位置：`rendering/post.glsl` 的 `OMNI_COMPOSITE7_PASS` 分支先引入共享声明、材质与时间抗锯齿文件，再引入本文件，
    最后 `void main(){ WriteTaaHistory(); }` 调用；输出的 `compositeOutput7` 由主文件的程序块声明。
可复制示例：`WriteTaaHistory();`（要求调用方已提供 `texelCoord`、`texCoord` 与 `colortex1`、`colortex6`）。
设计原因与取舍：时间重投影与相机速度函数在 `effects/clarity/antialiasing.glsl`，本文件只做程序级的选项分派与写出，
    与原程序 `composite7.fsh` 的主循环一比一对应；下界分支沿用原程序把两个深度打包进透明度通道的做法。
*/
#ifndef OMNI_POST_TAA_INCLUDED // 只引入一次，避免函数重复定义。
#define OMNI_POST_TAA_INCLUDED // 置上标记，后续再次引用直接跳过。

void WriteTaaHistory(){
	#ifdef OMNI_TAA // 开启时间抗锯齿才做重投影。
		float materialIDs = floor(texelFetch(colortex6, texelCoord, 0).b * 255.0); // 读当前像素的材质编号。
		float depth = 1.0; // 供相机速度函数回填的代表深度。
		vec3 velocity = TaaCameraVelocity(depth, materialIDs); // 算当前像素相对上一帧的屏幕位移，并回填深度。
		vec4 taa = vec4(0.0); // 重投影结果。
		#ifdef OMNI_NETHER // 下界重投影额外回填参考深度，写回历史时要一起打包。
			float referenceDepth = 0.0; // 重投影后的参考深度。
		#endif

		// 先算出这个像素要不要用历史：三条宏分支各把要排除的材质标记为假，其余像素保持为真。
		bool reproject = true; // 默认走重投影。
		#if defined OMNI_DISABLE_HAND_TAA && defined OMNI_DISABLE_PLAYER_TAA_MOTION_BLUR // 手与玩家都排除。
			if (materialIDs == MATID_HAND || materialIDs == MATID_ENTITIES_PLAYER) reproject = false; // 这两类像素不用历史。
		#elif defined OMNI_DISABLE_HAND_TAA // 只排除手。
			if (materialIDs == MATID_HAND) reproject = false; // 手不用历史。
		#elif defined OMNI_DISABLE_PLAYER_TAA_MOTION_BLUR // 只排除玩家。
			if (materialIDs == MATID_ENTITIES_PLAYER) reproject = false; // 玩家不用历史。
		#endif
		if (!reproject){ // 被排除的像素直接用当前帧颜色。
			taa = texelFetch(colortex1, texelCoord, 0); // 当前帧颜色。
		}else{ // 其余像素走时间重投影。
			#ifdef OMNI_NETHER // 下界用带参考深度的重投影。
				taa = TemporalReprojection(texCoord, velocity, depth, referenceDepth); // 邻域裁剪后把历史混进当前帧，并回填参考深度。
			#else // 其余维度用主世界版重投影。
				taa = TemporalReprojection(texCoord, velocity, depth); // 邻域裁剪后把历史混进当前帧。
			#endif
		}
	#else // 关闭时间抗锯齿时原样复制当前帧。
		vec4 taa = texelFetch(colortex1, texelCoord, 0); // 当前帧颜色与深度。
		#ifdef OMNI_NETHER // 下界直接沿用当前帧的深度当作参考深度。
			float referenceDepth = taa.a; // 当前帧深度就是参考深度。
		#endif
	#endif

	#ifdef OMNI_NETHER // 下界把参考深度与当前深度打包进七号画面透明度通道。
		compositeOutput7 = vec4(saturate(taa.rgb), Pack2x16(saturate(vec2(referenceDepth, taa.a)))); // 颜色加两个深度的打包值。
	#else // 其余维度直接写回。
		compositeOutput7 = taa; // 写回七号，作为下一帧的历史。
	#endif
}
#endif // 文件守卫结束。
