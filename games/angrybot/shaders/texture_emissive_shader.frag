#version 400 core

in vec2 FragTextureCoord;

out vec4 FragColor;

//uniform sampler2D tex;
uniform sampler2D texture_emissive;

void main() {
    FragColor = texture(texture_emissive, FragTextureCoord);

    //  FragColor = vec4(0.5, 0.9, 0.2, 1.0);
}
