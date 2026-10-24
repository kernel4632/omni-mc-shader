#version 330 core
// 阴影顶点阶段：用方向光的视图投影矩阵把地形投影到深度图，只关心位置。
// 调用位置：测试世界每帧第一遍绘制，目标是一张只有深度的阴影贴图。
// 设计原因与取舍：与地形共用同一套顶点缓冲，属性位置零就是世界坐标，
// 因此不需要第二份网格，也不需要颜色与法线。
layout(location = 0) in vec3 aPosition; // 方块角点的世界坐标。

uniform mat4 uLightViewProjection; // 方向光的视图投影矩阵。

void main()
{
    gl_Position = uLightViewProjection * vec4(aPosition, 1.0); // 直接投影到光源裁剪空间。
}
