#version 400 core

in vec2 fragTextureCoord;

out vec4 fragColor;

//uniform sampler2D tex;
uniform sampler2D texture_emissive;

void main() {
    fragColor = texture(texture_emissive, fragTextureCoord);
}
