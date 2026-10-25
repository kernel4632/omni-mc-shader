#version 330 core
// 地形顶点阶段：传递世界坐标、材质与遮蔽，并让草叶和树冠随风轻摆。
// 调用位置：测试世界的地形绘制；顶点数据由 Python 侧按高度图与植被生成。
// 设计原因与取舍：摆动只在顶点阶段做，片元阶段不必知道风；
// 阴影阶段用同一个公式重算位置，树影才会跟着树冠一起动，不会留在原地。
layout(location = 0) in vec3 aPosition;  // 方块角点的世界坐标。
layout(location = 1) in vec3 aNormal;  // 面法线，顶面朝上，侧面朝外。
layout(location = 2) in vec3 aColor;  // 面的基础颜色。
layout(location = 3) in float aOcclusion;  // 预先算好的逐角环境光遮蔽。
layout(location = 4) in float aMaterial;  // 材质编号，片元阶段据此选粗糙度与透光。
layout(location = 5) in float aSway;  // 风摆权重，零是贴地，一是枝条末端。

uniform mat4 uViewProjection;  // 相机视图投影矩阵。
uniform float uTime;  // 场景时间，驱动风摆。
uniform float uWind;  // 风摆幅度，米；零可以完全关掉动画。

out vec3 vWorldPosition;  // 片元阶段用来做阴影步进与雾。
out vec3 vNormal;  // 世界空间法线。
out vec3 vColor;  // 基础颜色。
out float vOcclusion;  // 环境光遮蔽。
out float vMaterial;  // 材质编号。

void main()
{
    vec3 position = aPosition;  // 先复制一份，再叠加风摆。
    float phase = aPosition.x * 0.62 + aPosition.z * 0.41;  // 用位置当相位，整片植被不会同步摆动。
    float gust = 0.65 + 0.35 * sin(uTime * 0.37 + aPosition.x * 0.05);  // 低频阵风，让摆动时强时弱。
    position.x += sin(uTime * 1.55 + phase) * 0.10 * aSway * uWind * gust;  // 横向摆动。
    position.z += cos(uTime * 1.23 + phase * 1.31) * 0.07 * aSway * uWind * gust;  // 纵向摆动错开相位。
    position.y += sin(uTime * 2.10 + phase * 0.7) * 0.025 * aSway * uWind;  // 竖向轻微起伏。
    vWorldPosition = position;  // 传递摆动后的世界坐标。
    vNormal = aNormal;  // 法线不做模型变换，地形网格已经按世界坐标生成。
    vColor = aColor;  // 颜色原样传递。
    vOcclusion = aOcclusion;  // 遮蔽原样传递。
    vMaterial = aMaterial;  // 材质编号原样传递。
    gl_Position = uViewProjection * vec4(position, 1.0);  // 投影到裁剪空间。
}
