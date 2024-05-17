
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
    -1.0f, 1.0f,  0.0f,
    1.0f,  1.0f,  0.0f,
    -1.0f, -1.0f, 0.0f,
    -1.0f, -1.0f, 0.0f,
    1.0f,  1.0f,  0.0f,
    1.0f,  -1.0f, 0.0f
};

char* vertexShaderSrc = "#version 400 core\n"
"in vec3 aPos;\n"
"void main()\n"
"{\n"
"gl_Position = vec4(aPos, 1.0f);\n"
"}\n";

char* pathTracerSrcPath = "../../pathtracer.glsl";

struct
{
    uint32_t program;
    uint32_t vao;
    
    // Uniforms
    uint32_t resolution;
    uint32_t frameId;
    uint32_t accumulate;
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
void InitState(Vec3* camPos, Vec2* camRot);
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
    
    uint32_t frameCount = 0;
    Vec3 camPos;
    Vec2 camRot;
    InitState(&camPos, &camRot);
    
    while(!glfwWindowShouldClose(window))
    {
        glfwPollEvents();
        
        int width, height;
        glfwGetFramebufferSize(window, &width, &height);
        
        // Update state
        FirstPersonCamera(&camPos, &camRot);
        
        // Render
        glViewport(0, 0, width, height);
        
        glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        
        glUseProgram(renderState.program);
        
        // Set uniforms
        glUniform2f(renderState.resolution, (float)width, (float)height);
        glUniform1ui(renderState.frameId, frameCount);
        glUniform3f(renderState.cameraPos, camPos.x, camPos.y, camPos.z);
        glUniform2f(renderState.cameraAngle, camRot.x, camRot.y);
        
        glBindVertexArray(renderState.vao);
        glDrawArrays(GL_TRIANGLES, 0, sizeof(fullScreenQuad) / (sizeof(float) * 3));
        glfwSwapBuffers(window);
        
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
    
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 3 * sizeof(float), (void*)0);
    glEnableVertexAttribArray(0);
    
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
    res.accumulate  = glGetUniformLocation(res.program, "accumulate");
    res.cameraPos   = glGetUniformLocation(res.program, "cameraPos");
    res.cameraAngle = glGetUniformLocation(res.program, "cameraAngle");
    
    glDeleteShader(vertShader);
    glDeleteShader(fragShader);
    
    return res;
}

void InitState(Vec3* camPos, Vec2* camRot)
{
    camPos->x = 0.0f;
    camPos->y = 0.0f;
    camPos->z = 0.0f;
    
    camRot->x = 0.0f;
    camRot->y = 0.0f;
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