include(GNURadioSharedDependencies)

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
  set(_vir_headers
      simd.h
      simdize.h
      simd_version.h
      simd_concepts.h
      simd_permute.h
      detail.h
      constexpr_wrapper.h
      struct_reflect.h)
  list(TRANSFORM _vir_headers PREPEND "${vir-simd_SOURCE_DIR}/vir/")
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
