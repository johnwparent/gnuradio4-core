include("${CMAKE_CURRENT_LIST_DIR}/GNURadioSharedDependencies.cmake")

function(ObtainOrFindVirSIMD)
  if(FETCH)
    FetchContent_Declare(
      vir-simd
      GIT_REPOSITORY https://github.com/mattkretz/vir-simd.git
      GIT_TAG v0.4.4
      EXCLUDE_FROM_ALL)
      set(GR_FETCH_MAKE_AVAILABLE_DEPS ${GR_FETCH_MAKE_AVAILABLE_DEPS} vir-simd PARENT_SCOPE)
  else()
    find_path(vir-simd_SOURCE_DIR vir/simd.h)
    if(NOT vir-simd_SOURCE_DIR)
      message(
        FATAL_ERROR
          "vir-simd was not found. Install the vir headers under an include path, for example /usr/local/include/vir.")
    endif()
  endif()
endfunction()

# must run after FetchContent_MakeAvailable(): a fetched vir-simd_SOURCE_DIR does not exist until then, and a file set
# whose files fall outside its base directories is a hard generate-step error rather than a warning.
function(DefineVirTarget)
  add_library(vir INTERFACE)
  add_library(gnuradio4::vir ALIAS vir)
  if(MSVC)
    target_compile_definitions(vir INTERFACE NOMINMAX)
  endif()
  # every header vir-simd ships, rather than a hand-maintained closure of the ones GR4 includes
  # directly. vir-simd is header-only and small, so staging all of it costs nothing, and a curated
  # list silently omits whatever a downstream project includes that core does not: the list this
  # replaced covered <vir/simd.h> and <vir/simdize.h> but not <vir/simd_execution.h>, which
  # gnuradio4Library's SimdFFT.hpp includes, so an installed prefix was missing it.
  file(GLOB _vir_headers CONFIGURE_DEPENDS "${vir-simd_SOURCE_DIR}/vir/*.h")
  list(SORT _vir_headers)
  target_sources(vir
    INTERFACE
    FILE_SET HEADERS
    BASE_DIRS ${vir-simd_SOURCE_DIR}
    FILES ${_vir_headers})
  # BASE_DIRS is the whole fetched source tree, which would otherwise reach every consumer of gnuradio4::vir as a plain
  # -I under -Werror / /WX.
  set_target_properties(vir PROPERTIES SYSTEM ON)
endfunction()

set(GR_FETCH_MAKE_AVAILABLE_DEPS)
ObtainOrFindVirSIMD()
ObtainOrFindHttpLib()
if(ENABLE_BENCH OR ENABLE_TESTING)
  ObtainOrFindUT()
endif()

if(GR_FETCH_MAKE_AVAILABLE_DEPS)
  FetchContent_MakeAvailable(${GR_FETCH_MAKE_AVAILABLE_DEPS})
endif()

DefineVirTarget()
if(EMSCRIPTEN AND TARGET ut)
  SetupUtTargetForEmscripten()
endif()

CheckPythonAvailability()
