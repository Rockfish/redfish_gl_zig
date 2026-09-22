#version 330 core
layout(location = 0) in vec3 inPosition;

uniform mat4 matProjection;
uniform mat4 matView;

out vec3 TexCoord;

void main()
{
    TexCoord = inPosition;
    vec4 pos = matProjection * matView * vec4(inPosition, 1.0);
    gl_Position = pos.xyww;
}
