#version 330 core
// 植物卡片顶点阶段：叶、草、花共用，负责风摆、世界坐标与纹理坐标传递。
// 调用位置：测试世界的叶片、草丛与野花绘制；阴影阶段另有一份只输出深度的版本，
// 但风摆公式必须与本文件完全一致，否则叶片在动、影子不动。
// 设计原因与取舍：卡片是双面薄片，法线朝外但不参与背面剔除；
// 片的底边风摆权重为零，根固定在土里，顶端才随阵风摆动。
layout(location = 0) in vec3 aPosition; // 世界坐标。
layout(location = 1) in vec3 aNormal; // 卡片法线。
layout(location = 2) in vec2 aUv; // 卡片纹理坐标。
layout(location = 3) in vec3 aColor; // 逐顶点色调。
layout(location = 4) in float aSway; // 风摆权重，底边为零、顶端为一。

uniform mat4 uViewProjection; // 相机视图投影。
uniform float uTime; // 场景时间。
uniform float uWind; // 风摆幅度。

out vec3 vWorldPosition; // 世界坐标。
out vec3 vNormal; // 世界法线。
out vec2 vUv; // 纹理坐标。
out vec3 vColor; // 色调。
out float vSway; // 风摆权重。

void main()
{
    vec3 position = aPosition;
    float phase = aPosition.x * 0.62 + aPosition.z * 0.41;
    float gust = 0.65 + 0.35 * sin(uTime * 0.37 + aPosition.x * 0.05);
    position.x += sin(uTime * 1.55 + phase) * 0.10 * aSway * uWind * gust;
    position.z += cos(uTime * 1.23 + phase * 1.31) * 0.07 * aSway * uWind * gust;
    position.y += sin(uTime * 2.10 + phase * 0.7) * 0.025 * aSway * uWind;
    vWorldPosition = position;
    vNormal = aNormal;
    vUv = aUv;
    vColor = aColor;
    vSway = aSway;
    gl_Position = uViewProjection * vec4(position, 1.0);
}
