#version 330 core
// 全屏三角形：不绑定顶点缓冲，直接用顶点编号算出三个屏幕角点。
// 调用位置：等值测试与测试世界的全屏阶段；每个阶段各自声明版本。
void main()
{
    vec2 corner = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));  // 三个顶点覆盖整个屏幕。
    gl_Position = vec4(corner * 2.0 - 1.0, 0.0, 1.0);  // 零到二映射到裁剪空间的负一到一。
}
