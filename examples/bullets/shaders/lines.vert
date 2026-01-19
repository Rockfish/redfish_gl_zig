#version 410 core
layout (location = 0) in vec3 inPosition;
layout (location = 1) in vec4 inColor;


uniform mat4 matView;
uniform mat4 matProjection;

out vec4 vertexColor;

void main()
{
    vertexColor = inColor;
    gl_Position = matProjection * matView * vec4(inPosition, 1.0);
}