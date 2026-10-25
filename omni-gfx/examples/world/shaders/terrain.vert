#version 330 core
// 地形顶点阶段：把连续高度场的世界坐标与法线传给片元。
// 调用位置：测试世界场景与阴影阶段的透明地形绘制。
// 设计原因与取舍：地形没有骨骼或风摆，顶点只做一次视图投影；
// 所有材质混合、法线扰动与光照都在片元阶段按世界坐标计算。
layout(location = 0) in vec3 aPosition; // 世界坐标。
layout(location = 1) in vec3 aNormal; // 高度场法线。

uniform mat4 uViewProjection; // 相机视图投影。

out vec3 vWorldPosition; // 世界坐标。
out vec3 vNormal; // 世界法线。

void main()
{
    vWorldPosition = aPosition;
    vNormal = aNormal;
    gl_Position = uViewProjection * vec4(aPosition, 1.0);
}
