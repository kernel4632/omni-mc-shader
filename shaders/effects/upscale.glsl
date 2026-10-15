// 最终显示前的可选边缘自适应重采样：这里通过邻域颜色平滑边缘，不承诺真超分辨率重建。
// 调用位置：final.glsl 的最终颜色输出阶段。
// 调用示例：vec3 outputColor = omniUpscale(scene, uv);
// 设计取舍：独立文件保护宏与玩家开关，避免重复包含时错误改写 OMNI_UPSCALE；默认保持关闭。
#ifndef OMNI_UPSCALE_INCLUDED
#define OMNI_UPSCALE_INCLUDED
// @effect {"label":{"zh_cn":"超分","en_us":"Upscaling"}}
// @option {"label":{"zh_cn":"超分开关","en_us":"Edge-adaptive upscale"},"description":{"zh_cn":"按亮度梯度确定边缘方向后用多瓣核重采样；内部渲染分辨率低于输出时最能减少锯齿。","en_us":"Multi-lobe resample guided by luminance edges; most effective when the internal render resolution is below the output."}}
//#define OMNI_UPSCALE
// @option {"label":{"zh_cn":"超分强度","en_us":"Upscale strength"},"description":{"zh_cn":"边缘平滑的强度；取零等于关闭。","en_us":"Strength of the edge smoothing; zero equals off."},"slider":true}
#define OMNI_UPSCALE_STRENGTH 1.0 // [0.0 0.25 0.5 0.75 1.0]
// 共用颜色与屏幕输入。
#include "/common/math.glsl"
#include "/common/uniforms.glsl"
// 沿亮度梯度旋转采样瓣，平坦区保留当前颜色；这是重采样，不等同于真超分辨率算法。
vec3 omniUpscale(vec3 color, vec2 uv) {
    ivec2 center = ivec2(gl_FragCoord.xy); // 输出像素整数坐标。
    ivec2 high = ivec2(viewWidth-1.0,viewHeight-1.0); // 采样上限，避免越界。
    float luma[9]; int k = 0; // 三乘三邻域亮度。
    for (int y=-1;y<=1;y++) for (int x=-1;x<=1;x++) { luma[k]=omniLuminance(texelFetch(colortex0,clamp(center+ivec2(x,y),ivec2(0),high),0).rgb); k++; } // 逐点亮度。
    vec2 edgeDirection = vec2(luma[5]-luma[3],luma[1]-luma[7]); // 中心与四邻的水平垂直梯度。
    float strength = clamp(length(edgeDirection)*3.0,0.0,1.0)*OMNI_UPSCALE_STRENGTH; // 边缘越强重采样权重越大；强度选项整体放大或缩小。
    vec2 axis = length(edgeDirection)>1e-5 ? omniNormalize(vec3(edgeDirection,0.0)).xy : vec2(1.0,0.0); // 归一化边缘方向。
    vec3 sum = color; float weight = 1.0; // 当前像素先参与平均。
    for (int i=1;i<=3;i++) {
        float lobe = exp(-float(i)*float(i)*0.35); // 采样瓣衰减。
        ivec2 offset = ivec2(round(axis*float(i))); // 沿边缘方向的整数偏移。
        sum += texelFetch(colortex0,clamp(center+offset,ivec2(0),high),0).rgb * lobe; // 正向样本。
        sum += texelFetch(colortex0,clamp(center-offset,ivec2(0),high),0).rgb * lobe; // 反向样本。
        weight += 2.0*lobe; // 累积权重。
    }
    return mix(color,sum/weight,strength); // 平坦区保留原样。
}
#endif
