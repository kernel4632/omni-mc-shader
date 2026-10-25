#version 330 core
// 阴影顶点阶段：把地形与物体投影到方向光深度图。
// 调用位置：每帧第一遍阴影绘制，目标只有深度附件。
layout(location = 0) in vec3 aPosition;  // 世界坐标。

uniform mat4 uLightViewProjection;  // 方向光视图投影。

void main()
{
    gl_Position = uLightViewProjection * vec4(aPosition, 1.0);  // 光源裁剪空间。
}
