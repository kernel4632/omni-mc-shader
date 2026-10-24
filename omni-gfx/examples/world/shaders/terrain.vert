#version 330 core
// 地形顶点阶段：把体素方块的顶点与颜色传给片元，并输出世界坐标。
// 调用位置：测试世界的地形绘制；顶点数据由 Python 侧按高度图生成。
layout(location = 0) in vec3 aPosition;  // 方块角点的世界坐标。
layout(location = 1) in vec3 aNormal;  // 面法线，顶面朝上，侧面朝外。
layout(location = 2) in vec3 aColor;  // 面的基础颜色。
layout(location = 3) in float aOcclusion;  // 预先算好的环境光遮蔽。

uniform mat4 uViewProjection;  // 相机视图投影矩阵。

out vec3 vWorldPosition;  // 片元阶段用来做阴影步进与雾。
out vec3 vNormal;  // 世界空间法线。
out vec3 vColor;  // 基础颜色。
out float vOcclusion;  // 环境光遮蔽。

void main()
{
    vWorldPosition = aPosition;  // 世界坐标原样传递。
    vNormal = aNormal;  // 法线不做模型变换，地形网格已经按世界坐标生成。
    vColor = aColor;  // 颜色原样传递。
    vOcclusion = aOcclusion;  // 遮蔽原样传递。
    gl_Position = uViewProjection * vec4(aPosition, 1.0);  // 投影到裁剪空间。
}
