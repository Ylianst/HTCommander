cmake_minimum_required(VERSION 3.14)

if(POLICY CMP0153)
    cmake_policy(SET CMP0153 NEW)
endif()

set(PROJECT_NAME "flutter_tts")
project(${PROJECT_NAME} LANGUAGES CXX)
include(FetchContent)

FetchContent_Declare(nuget
    URL "https://dist.nuget.org/win-x86-commandline/v6.5.0/nuget.exe"
    URL_HASH SHA256=d5fce5185de92b7356ea9264b997a620e35c6f6c3c061e471e0dc3a84b3d74fd
    DOWNLOAD_NO_EXTRACT true
)

find_program(NUGET_EXE NAMES nuget)
if(NOT NUGET_EXE)
    message(STATUS "nuget.exe not found, trying to download or use cached version.")
    FetchContent_MakeAvailable(nuget)
    set(NUGET_EXE "${nuget_SOURCE_DIR}/nuget.exe")
endif()

execute_process(
        COMMAND ${NUGET_EXE} install Microsoft.Windows.CppWinRT
        -Version 2.0.210503.1
        -ExcludeVersion
        -OutputDirectory ${CMAKE_BINARY_DIR}/packages
        RESULT_VARIABLE NUGET_RESULT
)
if(NOT NUGET_RESULT EQUAL 0)
    message(FATAL_ERROR "Failed to install NuGet package Microsoft.Windows.CppWinRT.2.0.210503.1")
endif()

set(PLUGIN_NAME "flutter_tts_plugin")

add_library(${PLUGIN_NAME} SHARED
        "flutter_tts_plugin.cpp"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
        CXX_VISIBILITY_PRESET hidden
        VISIBILITY_INLINES_HIDDEN YES
)

target_compile_features(${PLUGIN_NAME} PUBLIC cxx_std_20)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
        "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

target_link_libraries(${PLUGIN_NAME} PRIVATE
        flutter
        flutter_wrapper_plugin
)

set_target_properties(${PLUGIN_NAME} PROPERTIES VS_PROJECT_IMPORT
        "${CMAKE_BINARY_DIR}/packages/Microsoft.Windows.CppWinRT/build/native/Microsoft.Windows.CppWinRT.props"
)

target_link_libraries(${PLUGIN_NAME} PRIVATE
        "${CMAKE_BINARY_DIR}/packages/Microsoft.Windows.CppWinRT/build/native/Microsoft.Windows.CppWinRT.targets"
)

set(flutter_tts_bundled_libraries "" PARENT_SCOPE)