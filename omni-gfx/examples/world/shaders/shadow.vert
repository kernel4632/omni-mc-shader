#version 330 core
// 不透明阴影顶点阶段：把地形、树干与岩石投影到方向光深度图。
// 调用位置：测试世界每帧第一遍阴影绘制，目标只有深度附件。
// 设计原因与取舍：树干与岩石的世界坐标就在位置属性零，不需要风摆；
// 树冠与草的摆动用自己的阴影顶点阶段，避免这里误读材质或颜色通道。
layout(location = 0) in vec3 aPosition; // 世界坐标。

uniform mat4 uLightViewProjection; // 方向光视图投影。

void main()
{
    gl_Position = uLightViewProjection * vec4(aPosition, 1.0);
}
