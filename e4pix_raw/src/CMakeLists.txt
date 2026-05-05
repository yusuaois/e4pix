# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(e4pix_raw_library VERSION 0.0.1 LANGUAGES C)

add_library(e4pix_raw SHARED
  "e4pix_raw.c"
)

set_target_properties(e4pix_raw PROPERTIES
  PUBLIC_HEADER e4pix_raw.h
  OUTPUT_NAME "e4pix_raw"
)

target_compile_definitions(e4pix_raw PUBLIC DART_SHARED_LIB)

if (ANDROID)
  # Support Android 15 16k page size
  target_link_options(e4pix_raw PRIVATE "-Wl,-z,max-page-size=16384")
endif()
