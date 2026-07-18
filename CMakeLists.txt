cmake_minimum_required(VERSION 3.24)
project(stdx
    VERSION 2.3.0
    LANGUAGES CXX
)

if(MSVC)
    message(FATAL_ERROR "MSVC is disallowed due to missing compiler features/extensions. Please use GCC or Clang instead.")
endif()

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Options
option(STDX_FETCH_FMT "Fetch fmt library automatically via FetchContent" ON)
option(STDX_FETCH_MAGIC_ENUM "Fetch magic_enum library automatically via FetchContent" ON)
option(STDX_FETCH_UNORDERED_DENSE "Fetch unordered_dense library automatically via FetchContent" ON)
option(STDX_FETCH_GSL "Fetch GSL library automatically via FetchContent" ON)
option(STDX_PROFILE "Enable chromium tracing" OFF)
option(STDX_WARNINGS_AS_ERRORS "Treat compile warnings as errors" ON)

# Version info for config.h
set(STDX_VERSION_STR "${PROJECT_VERSION}")
set(STDX_VERSION_MAJOR ${PROJECT_VERSION_MAJOR})
set(STDX_VERSION_MINOR ${PROJECT_VERSION_MINOR})
set(STDX_VERSION_PATCH ${PROJECT_VERSION_PATCH})
set(STDX_VERSION_PRE "") # Release version

# Platform detection
if(WIN32)
    set(STDX_WINDOWS 1)
else()
    set(STDX_WINDOWS 0)
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    set(STDX_LINUX 1)
else()
    set(STDX_LINUX 0)
endif()

if(APPLE)
    set(STDX_APPLE 1)
else()
    set(STDX_APPLE 0)
endif()

# Generate stdx/config.h
configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/cmake/config.h.in"
    "${CMAKE_CURRENT_BINARY_DIR}/include/stdx/config.h"
)

# Fetch or find dependencies
include(FetchContent)

# 1. fmt
if(STDX_FETCH_FMT)
    set(FMT_TEST OFF CACHE INTERNAL "")
    set(FMT_DOC OFF CACHE INTERNAL "")
    FetchContent_Declare(
        fmt
        URL https://github.com/fmtlib/fmt/archive/refs/tags/12.1.0.tar.gz
    )
    FetchContent_MakeAvailable(fmt)
else()
    find_package(fmt REQUIRED)
endif()

# 2. magic_enum
if(STDX_FETCH_MAGIC_ENUM)
    set(MAGIC_ENUM_OPT_BUILD_TESTS OFF CACHE INTERNAL "")
    set(MAGIC_ENUM_OPT_BUILD_EXAMPLES OFF CACHE INTERNAL "")
    FetchContent_Declare(
        magic_enum
        URL https://github.com/Neargye/magic_enum/archive/refs/tags/v0.9.7.tar.gz
    )
    FetchContent_MakeAvailable(magic_enum)
else()
    find_package(magic_enum REQUIRED)
endif()

# 3. unordered_dense
if(STDX_FETCH_UNORDERED_DENSE)
    FetchContent_Declare(
        unordered_dense
        URL https://github.com/martinus/unordered_dense/archive/refs/tags/v4.8.1.tar.gz
    )
    FetchContent_MakeAvailable(unordered_dense)
else()
    find_package(unordered_dense REQUIRED)
endif()

# 4. GSL
if(STDX_FETCH_GSL)
    set(GSL_TEST OFF CACHE INTERNAL "")
    FetchContent_Declare(
        gsl
        URL https://github.com/microsoft/GSL/archive/refs/tags/v4.2.2.tar.gz
    )
    FetchContent_MakeAvailable(gsl)
else()
    find_package(Microsoft.GSL REQUIRED)
endif()

# Map dependencies to targets (handling potential namespace differences)
if(TARGET fmt::fmt)
    set(FMT_TARGET fmt::fmt)
else()
    set(FMT_TARGET fmt)
endif()

if(TARGET magic_enum::magic_enum)
    set(MAGIC_ENUM_TARGET magic_enum::magic_enum)
else()
    set(MAGIC_ENUM_TARGET magic_enum)
endif()

if(TARGET unordered_dense::unordered_dense)
    set(UNORDERED_DENSE_TARGET unordered_dense::unordered_dense)
else()
    set(UNORDERED_DENSE_TARGET unordered_dense)
endif()

if(TARGET Microsoft.GSL::GSL)
    set(GSL_TARGET Microsoft.GSL::GSL)
elseif(TARGET GSL)
    set(GSL_TARGET GSL)
else()
    message(FATAL_ERROR "GSL target not found")
endif()

# Source files
set(STDX_SOURCES
    src/profiler.cc
    src/utility.cc
)

# Core library
add_library(stdx STATIC ${STDX_SOURCES})

# Target Include Directories
target_include_directories(stdx
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/include>
)

# Compiler Gated Warnings for Clang / GCC
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(stdx PRIVATE
        -Wall
        -Wextra
        -Wpedantic
        -Wconversion
        -Wshadow
        -Wno-gnu-statement-expression
        -Wno-gnu-statement-expression-from-macro-expansion
    )
    if(STDX_WARNINGS_AS_ERRORS)
        target_compile_options(stdx PRIVATE -Werror)
    endif()
endif()

# Compile definitions
target_compile_definitions(stdx PUBLIC MAGIC_ENUM_RANGE_MAX=255)
if(STDX_PROFILE)
    target_compile_definitions(stdx PUBLIC STDX_PROFILE)
endif()

# Link libraries
target_link_libraries(stdx
    PUBLIC
        ${FMT_TARGET}
        ${MAGIC_ENUM_TARGET}
        ${UNORDERED_DENSE_TARGET}
        ${GSL_TARGET}
)

# Testing configuration
option(STDX_BUILD_TESTS "Build Catch2 unit tests" ON)
option(STDX_FETCH_CATCH2 "Fetch Catch2 library automatically via FetchContent" ON)

if(STDX_BUILD_TESTS)
    enable_testing()

    if(STDX_FETCH_CATCH2)
        # Disable catch2 tests/docs to speed up build
        set(CATCH_BUILD_TESTING OFF CACHE INTERNAL "")
        set(CATCH_INSTALL_HELPERS OFF CACHE INTERNAL "")
        FetchContent_Declare(
            catch2
            URL https://github.com/catchorg/Catch2/archive/refs/tags/v3.12.0.tar.gz
        )
        FetchContent_MakeAvailable(catch2)
    else()
        find_package(Catch2 REQUIRED)
    endif()

    if(TARGET Catch2::Catch2WithMain)
        set(CATCH2_TARGET Catch2::Catch2WithMain)
    else()
        set(CATCH2_TARGET Catch2WithMain)
    endif()

    # Collect test source files
    file(GLOB_RECURSE STDX_TEST_SOURCES
        "tests/*.cc"
    )

    add_executable(stdx_tests ${STDX_TEST_SOURCES})
    target_link_libraries(stdx_tests PRIVATE stdx ${CATCH2_TARGET})

    target_compile_features(stdx_tests PRIVATE cxx_std_23)

    if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
        target_compile_options(stdx_tests PRIVATE
            -Wall
            -Wextra
            -Wpedantic
            -Wconversion
            -Wshadow
            -Wno-gnu-statement-expression
            -Wno-gnu-statement-expression-from-macro-expansion
        )
        if(STDX_WARNINGS_AS_ERRORS)
            target_compile_options(stdx_tests PRIVATE -Werror)
        endif()
    endif()

    if(CMAKE_CXX_COMPILER_ID MATCHES "GNU")
        target_link_options(stdx_tests PRIVATE -static)
    endif()

    target_include_directories(stdx_tests PRIVATE tests)

    add_test(NAME stdx_tests COMMAND stdx_tests)
endif()

