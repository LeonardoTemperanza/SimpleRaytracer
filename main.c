
#include "assert.h"
#include "stdbool.h"
#include "stdio.h"
#include "stdint.h"

// Unity build
#include "glad.c"
#include "GLFW/glfw3.h"

void ErrorCallback(int error, const char* description)
{
    fprintf(stderr, "Error: %s\n", description);
}

float fullScreenQuad[] =
{
    // Vertices         // Texture Coords
    -1.0f, 1.0f,  0.0f, 0.0f, 1.0f,
    1.0f,  1.0f,  0.0f, 1.0f, 1.0f,
    -1.0f, -1.0f, 0.0f, 0.0f, 0.0f,
    -1.0f, -1.0f, 0.0f, 0.0f, 0.0f,
    1.0f,  1.0f,  0.0f, 1.0f, 1.0f,
    1.0f,  -1.0f, 0.0f, 1.0f, 0.0f
};

char* vertexShaderSrc = "#version 400 core\n"
"in vec3 aPos;\n"
"void main()\n"
"{\n"
"gl_Position = vec4(aPos, 1.0f);\n"
"}\n";

char* tex2ScreenShaderSrc = "#version 400 core\n"
"in vec2 texCoords;\n"
"out vec4 fragColor;\n"
"uniform sampler2D tex;\n"
"void main()\n"
"{\n"
"fragColor = texture(tex, texCoords);\n"
"}\n";

char* pathTracerSrcPath = "../../pathtracer.glsl";

struct
{
    uint32_t program;
    uint32_t tex2ScreenProgram;  // For rendering a texture to the screen
    uint32_t vao;
    
    // For progressive rendering
    uint32_t pingPongFbo[2];
    uint32_t pingPongTex[2];
    
    // Uniforms
    uint32_t resolution;
    uint32_t frameId;
    uint32_t accumulate;
    uint32_t frameAccum;
    uint32_t cameraPos;
    uint32_t cameraAngle;
} typedef RenderState;

struct
{
    float x, y, z;
} typedef Vec3;

struct
{
    float x, y;
} typedef Vec2;

struct
{
    Vec2 mouseDelta;
    bool rightClick;
    bool pressedW, pressedA, pressedS, pressedD;
} typedef Input;

// Returns shader program
RenderState InitRendering();
void FirstPersonCamera(Vec3* camPos, Vec2* camRot);

char* LoadEntireFile(const char* fileName);

int main()
{
    glfwSetErrorCallback(ErrorCallback);
    
    bool ok = glfwInit();
    assert(ok);
    
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 0);
    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);  // Required on macOS
    glfwWindowHint(GLFW_OPENGL_DEBUG_CONTEXT, GL_TRUE);
    
    GLFWwindow* window = glfwCreateWindow(1200, 1000, "Simple Path Tracer", NULL, NULL);
    assert(window);
    
    glfwMakeContextCurrent(window);
    gladLoadGL();
    //gladLoadGLLoader((GLADloadproc)glfwGetProcAddress);
    glfwSwapInterval(1);  // Enable vsync
    
    RenderState renderState = InitRendering();
    
    // Initialize state
    uint32_t accumulate = true;
    uint32_t frameCount = 0;
    Vec3 camPos = {0};
    Vec2 camRot = {0};
    
    while(!glfwWindowShouldClose(window))
    {
        glfwPollEvents();
        
        int width, height;
        glfwGetFramebufferSize(window, &width, &height);
        
        // Update state
        FirstPersonCamera(&camPos, &camRot);
        
        glViewport(0, 0, width, height);
        //glBindFramebuffer(GL_FRAMEBUFFER, renderState.pingPongFbo[1]);
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        
        // Render to framebuffer
        glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        glUseProgram(renderState.program);
        
        // Set uniforms
        glUniform2f(renderState.resolution, (float)width, (float)height);
        glUniform1ui(renderState.frameId, frameCount);
        glUniform1ui(renderState.accumulate, accumulate);
        glUniform3f(renderState.cameraPos, camPos.x, camPos.y, camPos.z);
        glUniform2f(renderState.cameraAngle, camRot.x, camRot.y);
        glBindTexture(GL_TEXTURE_2D, renderState.pingPongTex[0]);
        
        glBindVertexArray(renderState.vao);
        glDrawArrays(GL_TRIANGLES, 0, sizeof(fullScreenQuad) / (sizeof(float) * 3));
        
#if 0
        // Render produced image to default framebuffer
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        glUseProgram(renderState.tex2ScreenProgram);
        glBindTexture(GL_TEXTURE_2D, renderState.pingPongTex[1]);
        
        glBindVertexArray(renderState.vao);
        glDrawArrays(GL_TRIANGLES, 0, sizeof(fullScreenQuad) / (sizeof(float) * 3));
#endif
        
        glfwSwapBuffers(window);
        
        // Swap framebuffer objects for next frame
        uint32_t tmp = renderState.pingPongFbo[0];
        renderState.pingPongFbo[0] = renderState.pingPongFbo[1];
        renderState.pingPongFbo[1] = tmp;
        tmp = renderState.pingPongTex[0];
        renderState.pingPongTex[0] = renderState.pingPongTex[1];
        renderState.pingPongTex[1] = tmp;
        
        ++frameCount;
    }
    
    glfwDestroyWindow(window);
    glfwTerminate();
    return 0;
}

RenderState InitRendering()
{
    RenderState res = {0};
    
    // Setup buffers
    uint32_t vbo;
    glGenBuffers(1, &vbo);
    
    glGenVertexArrays(1, &res.vao);
    
    glBindVertexArray(res.vao);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(fullScreenQuad), fullScreenQuad, GL_STATIC_DRAW);
    
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 5 * sizeof(float), (void*)0);
    glEnableVertexAttribArray(0);
    
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 5 * sizeof(float), (void*)(3 * sizeof(float))); 
    glEnableVertexAttribArray(1);
    
    // FBO for progressive rendering
    glGenFramebuffers(2, res.pingPongFbo);
    
    for(int i = 0; i < 2; ++i)
    {
        glBindFramebuffer(GL_FRAMEBUFFER, res.pingPongFbo[i]);
        uint32_t textureColorBuffer;
        glGenTextures(1, &textureColorBuffer);
        glBindTexture(GL_TEXTURE_2D, textureColorBuffer);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, 800, 600, 0, GL_RGB, GL_UNSIGNED_BYTE, NULL);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, textureColorBuffer, 0);
        
        res.pingPongTex[i] = textureColorBuffer;
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
    }
    
    
    if(glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
    {
        fprintf(stderr, "Failed to create frame buffer object\n");
    }
    
    // Compile shaders
    uint32_t vertShader = glCreateShader(GL_VERTEX_SHADER);
    glShaderSource(vertShader, 1, &vertexShaderSrc, NULL);
    glCompileShader(vertShader);
    int success;
    char infoLog[512];
    glGetShaderiv(vertShader, GL_COMPILE_STATUS, &success);
    if(!success)
    {
        glGetShaderInfoLog(vertShader, 512, NULL, infoLog);
        fprintf(stderr, "Vertex shader compilation failed: %s\n", infoLog);
    }
    
    char* fragSrc = LoadEntireFile(pathTracerSrcPath);
    uint32_t fragShader = glCreateShader(GL_FRAGMENT_SHADER);
    glShaderSource(fragShader, 1, &fragSrc, NULL);
    glCompileShader(fragShader);
    glGetShaderiv(fragShader, GL_COMPILE_STATUS, &success);
    if(!success)
    {
        glGetShaderInfoLog(fragShader, 512, NULL, infoLog);
        fprintf(stderr, "Fragment shader compilation failed: %s\n", infoLog);
    }
    
    res.program = glCreateProgram();
    glAttachShader(res.program, vertShader);
    glAttachShader(res.program, fragShader);
    glLinkProgram(res.program);
    glGetProgramiv(res.program, GL_LINK_STATUS, &success);
    if(!success)
    {
        glGetProgramInfoLog(res.program, 512, NULL, infoLog);
        fprintf(stderr, "Shader program linking failed: %s\n", infoLog);
    }
    
    // Setup uniforms
    res.resolution  = glGetUniformLocation(res.program, "resolution");
    res.frameId     = glGetUniformLocation(res.program, "frameId");
    res.accumulate  = glGetUniformLocation(res.program, "doAccumulate");
    res.frameAccum  = glGetUniformLocation(res.program, "frameAccum");
    res.cameraPos   = glGetUniformLocation(res.program, "cameraPos");
    res.cameraAngle = glGetUniformLocation(res.program, "cameraAngle");
    
    // Simple texture to screen shader
    uint32_t tex2Screen = glCreateShader(GL_FRAGMENT_SHADER);
    glShaderSource(tex2Screen, 1, &tex2ScreenShaderSrc, NULL);
    glCompileShader(tex2Screen);
    glGetShaderiv(tex2Screen, GL_COMPILE_STATUS, &success);
    if(!success)
    {
        glGetShaderInfoLog(tex2Screen, 512, NULL, infoLog);
        fprintf(stderr, "Simple fragment shader compilation failed: %s\n", infoLog);
    }
    
    res.tex2ScreenProgram = glCreateProgram();
    glAttachShader(res.tex2ScreenProgram, vertShader);
    glAttachShader(res.tex2ScreenProgram, tex2Screen);
    glLinkProgram(res.tex2ScreenProgram);
    glGetProgramiv(res.tex2ScreenProgram, GL_LINK_STATUS, &success);
    if(!success)
    {
        glGetProgramInfoLog(res.tex2ScreenProgram, 512, NULL, infoLog);
        fprintf(stderr, "Texture to screen shader program linking failed: %s\n", infoLog);
    }
    
    glDeleteShader(vertShader);
    glDeleteShader(fragShader);
    glDeleteShader(tex2Screen);
    
    return res;
}

void FirstPersonCamera(Vec3* camPos, Vec2* camRot)
{
    Vec3 prevPos = *camPos;
    Vec2 prevRot = *camRot;
    
}

char* LoadEntireFile(const char* fileName)
{
    FILE* f = fopen(fileName, "rb");
    if(!f)
    {
        char* res = malloc(1);
        *res = '\0';
        return res;
    }
    
    fseek(f, 0, SEEK_END);
    size_t fileSize = ftell(f);
    fseek(f, 0, SEEK_SET);
    
    char* res = malloc(fileSize + 1);
    fread(res, fileSize, 1, f);
    res[fileSize] = '\0';
    
    fclose(f);
    
    return res;
}