# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "whisper_voice")
project(${PROJECT_NAME} LANGUAGES C CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed.
set(PLUGIN_NAME "whisper_voice_plugin")

# === whisper.cpp ===
# A pinned release, downloaded once into ../third and checked against its
# SHA-256, unless WHISPER_CPP_DIR points at a whisper.cpp source tree.
set(WHISPER_CPP_VERSION "1.9.5")
set(WHISPER_CPP_SHA256
  "ff1a9053feb509ff9d7729703355541ae9690073a6b1c40eb692c962e0dc1720")
set(WHISPER_CPP_DIR "" CACHE PATH
  "whisper.cpp source tree; empty downloads the pinned release")

if(WHISPER_CPP_DIR)
  set(_whisper_src "${WHISPER_CPP_DIR}")
else()
  set(_third "${CMAKE_CURRENT_SOURCE_DIR}/../third")
  set(_whisper_src "${_third}/whisper.cpp-${WHISPER_CPP_VERSION}")
  if(NOT EXISTS "${_whisper_src}/CMakeLists.txt")
    set(_archive "${_third}/whisper.cpp-${WHISPER_CPP_VERSION}.tar.gz")
    set(_unpack "${_third}/unpack")
    message(STATUS "Downloading whisper.cpp ${WHISPER_CPP_VERSION}")
    file(DOWNLOAD
      "https://github.com/ggml-org/whisper.cpp/archive/refs/tags/v${WHISPER_CPP_VERSION}.tar.gz"
      "${_archive}"
      EXPECTED_HASH SHA256=${WHISPER_CPP_SHA256}
      STATUS _status)
    list(GET _status 0 _code)
    if(NOT _code EQUAL 0)
      file(REMOVE "${_archive}")
      message(FATAL_ERROR "Could not download whisper.cpp (${_status}). "
        "Set WHISPER_CPP_DIR to a whisper.cpp ${WHISPER_CPP_VERSION} source tree.")
    endif()
    # Unpack beside the final folder and move it into place, so an
    # interrupted unpack is never taken for a complete tree.
    file(REMOVE_RECURSE "${_unpack}")
    file(MAKE_DIRECTORY "${_unpack}")
    execute_process(
      COMMAND "${CMAKE_COMMAND}" -E tar xzf "${_archive}"
      WORKING_DIRECTORY "${_unpack}"
      RESULT_VARIABLE _rc)
    file(REMOVE "${_archive}")
    if(NOT _rc EQUAL 0)
      message(FATAL_ERROR "Could not unpack whisper.cpp into ${_unpack}")
    endif()
    file(RENAME "${_unpack}/whisper.cpp-${WHISPER_CPP_VERSION}" "${_whisper_src}")
    file(REMOVE_RECURSE "${_unpack}")
  endif()
endif()

# CPU only. The ggml CPU backend is built once per instruction set (plain
# x86-64 up to AVX-512) and the best one for the computer is loaded at run
# time, so every x64 PC works and newer ones run faster. No OpenMP: it would
# need vcomp140.dll beside the app.
set(CMAKE_POLICY_DEFAULT_CMP0077 NEW)
set(BUILD_SHARED_LIBS ON)
set(WHISPER_BUILD_TESTS OFF)
set(WHISPER_BUILD_EXAMPLES OFF)
set(WHISPER_BUILD_SERVER OFF)
set(WHISPER_ALL_WARNINGS OFF)
set(GGML_NATIVE OFF)
set(GGML_OPENMP OFF)
set(GGML_BACKEND_DL ON)
set(GGML_CPU_ALL_VARIANTS ON)
set(GGML_BUILD_TESTS OFF)
set(GGML_BUILD_EXAMPLES OFF)
add_subdirectory("${_whisper_src}" whisper.cpp EXCLUDE_FROM_ALL)

# === Plugin ===
add_library(${PLUGIN_NAME} SHARED
  "include/whisper_voice/whisper_voice_plugin_c_api.h"
  "whisper_voice_plugin_c_api.cpp"
  "whisper_voice_plugin.cpp"
  "whisper_voice_plugin.h"
  "mic_capture.cpp"
  "mic_capture.h"
  "speech_engine.cpp"
  "speech_engine.h"
)

# Apply a standard set of build settings that are configured in the
# application-level CMakeLists.txt.
apply_standard_settings(${PLUGIN_NAME})

# Symbols are hidden by default to reduce the chance of accidental conflicts
# between plugins.
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL NOMINMAX)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter flutter_wrapper_plugin whisper ggml winmm)

# Nothing links the CPU backends (ggml loads them), so list them here to be
# built and copied next to the app.
set(_ggml_backends "")
foreach(_backend ${GGML_AVAILABLE_BACKENDS})
  if(TARGET ${_backend})
    add_dependencies(${PLUGIN_NAME} ${_backend})
    list(APPEND _ggml_backends "$<TARGET_FILE:${_backend}>")
  endif()
endforeach()

# List of absolute paths to libraries that should be bundled with the plugin.
set(whisper_voice_bundled_libraries
  "$<TARGET_FILE:whisper>"
  "$<TARGET_FILE:ggml>"
  "$<TARGET_FILE:ggml-base>"
  ${_ggml_backends}
  PARENT_SCOPE
)
