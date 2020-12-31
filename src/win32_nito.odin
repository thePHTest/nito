package main
import stbi "../deps/odin-stb/stbi"
import vk "../vulkan_gen/vulkan/"
import glfw "../deps/odin-glfw/"
import glfw_bindings "../deps/odin-glfw/bindings"

import "core:runtime"
import "core:fmt"
import "core:slice"
import "core:mem"
import "core:math"
import "core:math/linalg"

Pixel :: struct {
    r: u8,
    g: u8,
    b: u8,
}

V2 :: distinct [2]f32; 

AppOffscreenBuffer :: struct {
    dim : V2,
    bits_per_channel : u8,
}

Brightness :: proc(p : Pixel) -> f32 {
    return (0.299*f32(p.r) + 0.587*f32(p.g) + 0.114*f32(p.b)); 
}

ComparePixels :: proc(left, right : Pixel) -> bool {
    return Brightness(left) > Brightness(right);
}

GlfwErrorCallback : glfw.Error_Proc : proc "c" (error: i32, description: cstring) {
    context = runtime.default_context();
    fmt.println("GLFW Error Callback: ", description);
}

main :: proc() {
    c := context;
    
	fmt.println("Hellope!");
    if !glfw.init() {
        fmt.println("Could not init GLFW!");
    }
    glfw.set_error_callback(GlfwErrorCallback);
    if !glfw.vulkan_supported() {
        fmt.println("GLFW says Vulkan is not supported!");
        return;
    }
    
    vk_extensions_count : u32;
    vk_extensions := glfw_bindings.GetRequiredInstanceExtensions(&vk_extensions_count);
    fmt.println("Extensions count: ", vk_extensions_count);
    for i in 0..<vk_extensions_count {
        fmt.println("Extensions: ", mem.ptr_offset(vk_extensions, int(i))^);
    }
    
    vk_instance_create_info : vk.InstanceCreateInfo;
    // NOTE: Skipping memset in glfw guide here. I believe Odin compiler guarantees everything to zero by default. 
    // https://www.glfw.org/docs/3.3/vulkan_guide.html
    vk_instance_create_info.enabledExtensionCount = vk_extensions_count;
    vk_instance_create_info.ppEnabledExtensionNames = vk_extensions;
    
    glfw.window_hint(glfw.CLIENT_API, int(glfw.NO_API));
    monitor_handle : glfw.Monitor_Handle;
    window_handle : glfw.Window_Handle;
    window := glfw.create_window(1920, 1080, "Nito", monitor_handle, window_handle);
    // TODO: How to check if window success? i.e. how to check if not default rawptr
    
    vk_surface : vk.SurfaceKHR;
    vk_allocator : vk.AllocationCallbacks;
    glfw_bindings.CreateWindowSurface(instance, window, &vk_allocator, &vk_surface);
    
    
    
    
    
    
    filename : cstring = "SmallSquareLogo.png";
    out_filename := "out.png";
    // filename : cstring = "DSC05949.jpg"; 
    x,y, comp : i32;
    info := stbi.info(filename, &x, &y, &comp);
    image := stbi.load(filename, &x, &y, &comp, comp);
	fmt.println(x, y, comp);
    
    out_image := make([dynamic]u8, x*y*comp);
    defer delete(out_image);
    for i in 0..<y {
        row := make([dynamic]Pixel, x);
        defer delete(row);
        for j in 0..<x {
            pixel_r := mem.ptr_offset(image, int(i*x*comp + j*comp));
            pixel_g := mem.ptr_offset(image, int(i*x*comp + j*comp + 1));
            pixel_b := mem.ptr_offset(image, int(i*x*comp + j*comp + 2));
            row[j] = Pixel{pixel_r^, pixel_g^, pixel_b^};
        }
        slice.sort_by(row[0:x], ComparePixels); 
        for j in 0..<x {
            pixel := row[j];
            out_image[i*x*comp + j*comp] = pixel.r;
            out_image[i*x*comp + j*comp + 1] = pixel.g;
            out_image[i*x*comp + j*comp + 2] = pixel.b;
        }
    }
    fmt.println(len(out_image));
    stbi.write_png(out_filename, int(x), int(y), int(comp), out_image[0:x*y*comp], int(x*comp));
    
    glfw.terminate();
    fmt.println("PROGRAM END");
}