cmake_minimum_required(VERSION 3.27)

project(
  gnuradio
  VERSION 4.0.0
  LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
set(CMAKE_VISIBILITY_INLINES_HIDDEN ON)
set(GR4_PKG_VERSION
    "${PROJECT_VERSION}-git"
    CACHE STRING "Version string used in gnuradio4.pc")

# Plugin install paths are versioned by the plugin ABI, so plugins built against
# different ABIs can be installed side by side. Read from the single source of truth.
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/core/include/gnuradio-4.0/Plugin.hpp" GR_PLUGIN_ABI_DEFINE
     REGEX "^#define[ \t]+GR_PLUGIN_CURRENT_ABI_VERSION[ \t]+[0-9]+")
string(REGEX MATCH "[0-9]+$" GR_PLUGIN_API_VERSION "${GR_PLUGIN_ABI_DEFINE}")
if(NOT GR_PLUGIN_API_VERSION)
  message(FATAL_ERROR "Could not read GR_PLUGIN_CURRENT_ABI_VERSION from core/include/gnuradio-4.0/Plugin.hpp")
endif()

set(CMAKE_POSITION_INDEPENDENT_CODE TRUE)

# User facing GR Configuration Options

# limit parallel compile/link jobs to prevent OOM with template-heavy TUs override with -DGR_BUILD_PARALLEL_LEVEL=<N>
# (CI with more RAM can raise this)
set(GR_BUILD_PARALLEL_LEVEL
    "6"
    CACHE STRING "Maximum parallel compile/link jobs")
option(GR4_USE_THIN_ARCHIVES "Build static archives as thin archives (non-relocatable when installed)" OFF)
option(GR4_USE_LIBCXX "Force libc++ when compiling with Clang" OFF)
if(CMAKE_GENERATOR MATCHES "Ninja")
  set_property(GLOBAL APPEND PROPERTY JOB_POOLS compile_pool=${GR_BUILD_PARALLEL_LEVEL} link_pool=2)
  set(CMAKE_JOB_POOL_COMPILE compile_pool)
  set(CMAKE_JOB_POOL_LINK link_pool)
endif()

if(CMAKE_CXX_COMPILER MATCHES "/em\\+\\+(-[a-zA-Z0-9.])?$") # if this hasn't been set before via e.g. emcmake
  message(" Transpiling to WASM: using: Emscripten (${CMAKE_CXX_COMPILER})")
  set(EMSCRIPTEN ON)
endif()

if(NOT MSVC)
  # user-facing override: USE_MOLD_LINKER=OFF forces fall-through to lld/default even if mold is installed.
  option(USE_MOLD_LINKER "Use mold as the linker when available (falls back to lld, then default)" ON)
endif()

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE
      "RelWithAssert"
      CACHE STRING "Default build type" FORCE)
endif()
set_property(
  CACHE CMAKE_BUILD_TYPE
  PROPERTY STRINGS
           None
           Debug
           Release
           RelWithAssert
           RelWithDebInfo
           MinSizeRel)

set(REGISTRY_DEFAULT ON)
if(CMAKE_BUILD_TYPE STREQUAL "MinSizeRel")
  set(REGISTRY_DEFAULT OFF)
endif()

# Determine if GR4 is built as a subproject (using add_subdirectory) or if it is the master project.
if(NOT DEFINED GR_TOPLEVEL_PROJECT)
  set(GR_TOPLEVEL_PROJECT OFF)
  if(CMAKE_CURRENT_SOURCE_DIR STREQUAL CMAKE_SOURCE_DIR)
    set(GR_TOPLEVEL_PROJECT ON)
    message(STATUS "CMake version: ${CMAKE_VERSION}")
  endif()
endif()

set(GR_USE_ADAPTIVE_CPP OFF) # Detect AdaptiveCpp via compiler executable name
if(CMAKE_CXX_COMPILER MATCHES ".*acpp.*" OR CMAKE_CXX_COMPILER MATCHES ".*adaptivecpp.*")
  set(GR_USE_ADAPTIVE_CPP ON)
  message(STATUS "Detected AdaptiveCpp based on compiler path: ${CMAKE_CXX_COMPILER}")
endif()

# Option affects GR4 build, as well as the behaviour of BlockLib cmake functions that are used in out-of-tree modules
option(GR_ENABLE_BLOCK_REGISTRY "Enable building the block registry" ${REGISTRY_DEFAULT})
option(USE_CCACHE "Use ccache if available" ON)
option(INTERNAL_ENABLE_BLOCK_PLUGINS "Enable building the plugin system" ${REGISTRY_DEFAULT})
option(WARNINGS_AS_ERRORS "Enable -Werror flags" ON)
option(TIMETRACE "Enable clang's -ftime-trace" OFF)
option(ADDRESS_SANITIZER "Enable address sanitizer" OFF)
option(UB_SANITIZER "Enable undefined behavior sanitizer" OFF)
option(THREAD_SANITIZER "Enable thread sanitizer" OFF)
option(ENABLE_TBB "Enable the TBB dependency for std::execution::par in gcc" OFF)
option(ENABLE_EXAMPLES "Enable Example Builds" ${GR_TOPLEVEL_PROJECT})
option(ENABLE_TESTING "Enable Test Builds" ${GR_TOPLEVEL_PROJECT})
option(ENABLE_BENCH "Include benchmarking in builds" ${GR_TOPLEVEL_PROJECT})
option(MIT_ONLY "Exclude modules with non-MIT/Apache-compatible licences" OFF)
option(GR_USE_FETCHCONTENT_DEPS "Allow CMake to download selected third-party dependencies with FetchContent" OFF)
option(GR_PACKAGING "Allow GNURadio Core to be packaged with CPack" OFF)

if(NOT DEFINED GR_DATA_CACHE_DIR)
  set(GR_DATA_CACHE_DIR
      "${CMAKE_CURRENT_BINARY_DIR}/gnuradio_cache"
      CACHE PATH "Writeable system path where GR should store its cached data (for example, /var/lib/gnuradio4/cache)")
endif()

set(GR_MAX_WASM_THREAD_COUNT
    60
    CACHE STRING "Max number of threads for WASM pthread pool")
add_compile_definitions(GR_MAX_WASM_THREAD_COUNT=${GR_MAX_WASM_THREAD_COUNT}) # propagate to C++
set(GR4_PKGCONFIG_EXTRA_LIBS "")

# End user GR configuration

if(ENABLE_TESTING
   AND (UNIX
        OR APPLE
        OR WIN32))
  include(CTest)
  list(APPEND CMAKE_CTEST_ARGUMENTS "--output-on-failure")
  enable_testing()
  message("Building Tests and benchmarks.")
endif()

include(GNUInstallDirs)
include(cmake/SetupCompilerBehavior.cmake)
include(cmake/CompilerWarnings.cmake)
include(cmake/Utils.cmake)
include(cmake/GrInstall.cmake)
if(ENABLE_TESTING)
  include(cmake/GnuRadioTestHelpers.cmake)
endif()

if(EMSCRIPTEN OR NOT GR_ENABLE_BLOCK_REGISTRY)
  set(INTERNAL_ENABLE_BLOCK_PLUGINS OFF)
endif()

if((ADDRESS_SANITIZER AND UB_SANITIZER)
   OR (ADDRESS_SANITIZER AND THREAD_SANITIZER)
   OR (UB_SANITIZER AND THREAD_SANITIZER))
  message(FATAL_ERROR "Only one sanitizer can be enabled at a time.")
endif()

if(GR_USE_ADAPTIVE_CPP
   AND ((ADDRESS_SANITIZER
         OR UB_SANITIZER
         OR THREAD_SANITIZER)))
  message(
    FATAL_ERROR
      "SYCL is incompatible with ADDRESS_SANITIZER=${ADDRESS_SANITIZER} or UB_SANITIZER=${UB_SANITIZER} or THREAD_SANITIZER=${THREAD_SANITIZER}."
  )
endif()

# blocklib_generator is a build process dependency, add it before everything
add_subdirectory(blocklib_generator)

add_library(gnuradio-options INTERFACE)
add_library(gnuradio4::gnuradio-options ALIAS gnuradio-options)


message(
  STATUS
    "Is block registry enabled? (faster compile-times and when runtime or Python wrapping APIs are not required) ${GR_ENABLE_BLOCK_REGISTRY}"
)
message(STATUS "Is plugin system enabled? ${INTERNAL_ENABLE_BLOCK_PLUGINS}")

set_project_warnings(gnuradio-options)

if(MSVC)
  target_compile_options(
    gnuradio-options
    INTERFACE /Zc:preprocessor # conforming preprocessor, required for __VA_OPT__ (GR_MAKE_REFLECTABLE et al.)
              /Zc:__cplusplus # report the real __cplusplus value rather than 199711L
              /bigobj # required for sections larger than 2^16 (most GR template tus)
              /utf-8
              /external:W0 # required for /external:I
              /external:env:INCLUDE # the STL and Windows SDK headers are external too
              /vmg)
  target_compile_definitions(
    gnuradio-options
    INTERFACE _CRT_SECURE_NO_WARNINGS _SILENCE_CXX20_OLD_SHARED_PTR_ATOMIC_SUPPORT_DEPRECATION_WARNING)
endif()

if(EMSCRIPTEN)
  SetupEmscriptenGnuRadioOptions()
endif()

if(NOT (TARGET magic_enum))
  SetupMagicEnumTarget()
endif()

include(cmake/GnuRadioDependencies.cmake)

add_subdirectory(bench) # custom ut addon for microbenchmarking; header/target always published,
                        # only the sample benchmark is gated on ENABLE_BENCH

add_subdirectory(core)
add_subdirectory(meta)

if(ENABLE_TESTING
   AND (UNIX
        OR APPLE
        OR WIN32)
   AND ENABLE_COVERAGE)
  SetupCoverageSupport()
endif()

# Configure and install the pkg-config file TODO: This should become more granular - .pc for each in-tree module
set(GR4_PKGCONFIG_PLUGIN_LIB "")
if(TARGET gnuradio-plugin)
  set(GR4_PKGCONFIG_PLUGIN_LIB " -lgnuradio-plugin")
endif()
configure_file(cmake/gnuradio4.pc.in ${CMAKE_CURRENT_BINARY_DIR}/gnuradio4.pc @ONLY)

gr_install_artifact(
  FILES ${CMAKE_CURRENT_BINARY_DIR}/gnuradio4.pc 
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/pkgconfig # Standard location for .pc files
  COMPONENT DEVELOP
)

set(GR_CMAKECONFIG_INSTALL_DIR "${CMAKE_INSTALL_LIBDIR}/cmake/gnuradio4")

configure_package_config_file(cmake/gnuradio4Config.cmake.in "${CMAKE_CURRENT_BINARY_DIR}/gnuradio4Config.cmake"
                              INSTALL_DESTINATION "${GR_CMAKECONFIG_INSTALL_DIR}")

write_basic_package_version_file(
  "${CMAKE_CURRENT_BINARY_DIR}/gnuradio4ConfigVersion.cmake"
  VERSION "${GR4_PKG_VERSION}"
  COMPATIBILITY SameMajorVersion)

gr_install_artifact(
    TARGETS magic_enum
    EXPORT gnuradio4Targets
    PUBLIC_HEADER DESTINATION ${CMAKE_INSTALL_INCLUDEDIR} HEADERS_COMPONENT DEVELOP)
gr_install_artifact(TARGETS gnuradio-options EXPORT gnuradio4Targets COMPONENT DEVELOP)

gr_install_artifact(
  EXPORT gnuradio4Targets
  FILE gnuradio4Targets.cmake
  NAMESPACE gnuradio4::
  DESTINATION "${GR_CMAKECONFIG_INSTALL_DIR}"
  COMPONENT DEVELOP)

# DefineVirTarget() always attaches a header file set, whether vir-simd was fetched or found, so
# the install has to carry it in both cases: CMake refuses to export a target whose interface file
# sets are not installed. Staging the headers is also what makes the installed prefix
# self-contained -- a found vir-simd otherwise leaves gnuradio4::vir with no include directory a
# consumer can use, and the prefix silently depending on the provider's tree.
gr_install_artifact(
  TARGETS vir
  EXPORT gnuradio4Targets
  FILE_SET HEADERS
  DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
  HEADERS_COMPONENT DEVELOP)

if(TARGET gnuradio-plugin)
  gr_install_artifact(
    EXPORT gnuradio4PluginTargets
    FILE gnuradio4PluginTargets.cmake
    NAMESPACE gnuradio4::
    DESTINATION "${GR_CMAKECONFIG_INSTALL_DIR}"
    COMPONENT DEVELOP)
endif()

gr_install_artifact(FILES "cmake/Utils.cmake" "cmake/GrInstall.cmake" "cmake/GNURadioSharedDependencies.cmake" DESTINATION "${GR_CMAKECONFIG_INSTALL_DIR}" COMPONENT DEVELOP)

gr_install_artifact(FILES "${CMAKE_CURRENT_BINARY_DIR}/gnuradio4Config.cmake"
              "${CMAKE_CURRENT_BINARY_DIR}/gnuradio4ConfigVersion.cmake" DESTINATION "${GR_CMAKECONFIG_INSTALL_DIR}"
              COMPONENT DEVELOP)

gr_install_artifact(FILES "${CMAKE_CURRENT_SOURCE_DIR}/cmake/GnuRadioTestHelpers.cmake"
              "${CMAKE_CURRENT_SOURCE_DIR}/cmake/GrInnoSetup.cmake" DESTINATION "${GR_CMAKECONFIG_INSTALL_DIR}"
              COMPONENT DEVELOP)

# installer templates shared by every downstream GR installer
gr_install_artifact(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/packaging/innosetup"
        DESTINATION "${GR_CMAKECONFIG_INSTALL_DIR}/packaging"
        COMPONENT DEVELOP)

ReportConfigurationState()

if(GR_PACKAGING)
  include(cmake/CPackConfig.cmake)
endif()
