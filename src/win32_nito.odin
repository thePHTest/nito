package main
import stbi "../deps/odin-stb/stbi"
import vk "../vulkan_gen/vulkan/"
import sdl "../deps/odin-sdl2/"

import "core:runtime"
import "core:fmt"
import "core:slice"
import "core:mem"
import "core:math"
import "core:math/linalg"
import "core:strings"

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

VkGetInstanceProcAddr :: proc(instance: vk.Instance, pName: cstring) -> rawptr;

VkGetInstanceProc : VkGetInstanceProcAddr;

VkInstance : vk.Instance = nil;

VkSetProcAddress :: proc(p: rawptr, name: cstring) {
    (cast(^rawptr)(p))^  = VkGetInstanceProc(VkInstance, name);
}

main :: proc() {
    c := context;
    
    // Do SDL2
    // Any reason to not init everything?
    sdl.init(sdl.Init_Flags.Everything);
    vk_load_lib_res := sdl.vulkan_load_library(nil);
    fmt.println(sdl.get_error());
    if vk_load_lib_res != 0 {
        fmt.println("Unable to load vulkan lib!");
        fmt.println(sdl.get_error());
        return;
    }
    
    window := sdl.create_window("Nito",
                                i32(sdl.Window_Pos.Centered), i32(sdl.Window_Pos.Centered),
                                1920, 1080,
                                sdl.Window_Flags.Vulkan | sdl.Window_Flags.Shown);
    
    vk_proc_addr := sdl.vulkan_get_gk_get_instance_proc_addr();
    if vk_proc_addr == nil {
        fmt.println("Unable to get vk_proc_addr!");
        return;
    }
    VkGetInstanceProc = cast(VkGetInstanceProcAddr)vk_proc_addr;
    vk.load_proc_addresses(VkSetProcAddress);
    
    if ODIN_DEBUG {
        fmt.println("DEBUG BUILD");
        vk_layer_count : u32;
        vk.EnumerateInstanceLayerProperties(&vk_layer_count, nil);
        vk_layer_props := make([dynamic]vk.LayerProperties, vk_layer_count);
        vk.EnumerateInstanceLayerProperties(&vk_layer_count, &vk_layer_props[0]);
        
        for i in 0..<vk_layer_count {
            layer_name := string(vk_layer_props[i].layerName[:]);
            fmt.println("Found validation layer: ", layer_name);
        }
    }
    
    fmt.println(sdl.get_error());
    if window == nil {
        fmt.println("Unable to create sdl window!");
        fmt.println(sdl.get_error());
        return;
    }
    
    vk_extensions_count : u32 = 100;
    vk_extensions : [100]cstring;
    vk_get_instance_extensions_res := sdl.vulkan_get_instance_extensions(window, &vk_extensions_count, &vk_extensions[0]);
    fmt.println("Found ", vk_extensions_count, " Vulkan extensions.");
    if vk_get_instance_extensions_res == 0 {
        fmt.println("Failed to get Vulkan instance extensions!");
        fmt.println(sdl.get_error());
        return;
    }
    
    for i in 0..<vk_extensions_count {
        fmt.println("Extensions: ", vk_extensions[i]);
    }
    
    vk_app_info : vk.ApplicationInfo;
    vk_app_info.sType = vk.StructureType.APPLICATION_INFO;
    vk_app_info.pApplicationName = "Nito";
    vk_app_info.applicationVersion = vk.MAKE_VERSION(1, 0, 0);
    vk_app_info.pEngineName = "No Engine";
    vk_app_info.engineVersion = vk.MAKE_VERSION(1, 0, 0);
    vk_app_info.apiVersion = vk.API_VERSION_1_0;
    
    vk_create_info : vk.InstanceCreateInfo;
    vk_create_info.enabledExtensionCount = vk_extensions_count;
    vk_create_info.ppEnabledExtensionNames = &vk_extensions[0];
    vk_create_info.sType = vk.StructureType.INSTANCE_CREATE_INFO;
    vk_create_info.pApplicationInfo = &vk_app_info;
    vk_create_info.enabledLayerCount = 0;
    
    vk_instance_create_res := vk.CreateInstance(&vk_create_info, nil, &VkInstance);
    fmt.println("Created Vulkan Instance");
    if vk_instance_create_res != vk.Result.SUCCESS {
        fmt.println("Failed to create Vulkan Instance!");
        return;
    }
    defer vk.DestroyInstance(VkInstance, nil);
    vk.load_proc_addresses(VkSetProcAddress);
    
    
    vk_surface : vk.SurfaceKHR;
    create_surface_res := sdl.vulkan_create_surface(window, VkInstance, &vk_surface);
    if create_surface_res == sdl.Bool.False {
        fmt.println("Failed to create Vulkan surface!");
        return;
    }
    fmt.println("Created Vulkan Surface!");
    
    vk_drawable_width, vk_drawable_height : i32;
    sdl.vulkan_get_drawable_size(window, &vk_drawable_width, &vk_drawable_height);
    fmt.println("Vulkan drawable size: ", vk_drawable_width, " ", vk_drawable_height);
    
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
    
    fmt.println("PROGRAM END");
}