
set(FETCH OFF)
if(EMSCRIPTEN OR GR_USE_FETCHCONTENT_DEPS)
  set(FETCH ON)
  include(FetchContent)
endif()

include(CMakePackageConfigHelpers)
find_package(PkgConfig QUIET)

function(ObtainOrFindUT)
  if(FETCH)
    FetchContent_Declare(
      ut
      GIT_REPOSITORY https://github.com/boost-ext/ut.git
      GIT_TAG 53e17f25119598c6458d30351b260193096ba67e # latest tag as of 2023-04-02
      EXCLUDE_FROM_ALL)
      set(GR_FETCH_MAKE_AVAILABLE_DEPS ${GR_FETCH_MAKE_AVAILABLE_DEPS} ut PARENT_SCOPE)
  else()
    find_package(ut CONFIG QUIET)
    if(TARGET Boost::ut AND NOT TARGET ut)
      add_library(ut ALIAS Boost::ut)
    elseif(TARGET boost::ut AND NOT TARGET ut)
      add_library(ut ALIAS boost::ut)
    endif()
    if(NOT TARGET ut)
      find_path(GR_BOOST_UT_INCLUDE_DIR boost/ut.hpp)
      if(NOT GR_BOOST_UT_INCLUDE_DIR)
        message(FATAL_ERROR "Boost.UT was not found. Install libboost-ext-ut-dev, ut-devel, or a source-built Boost.UT.")
      endif()
      add_library(ut INTERFACE)
      target_include_directories(ut INTERFACE ${GR_BOOST_UT_INCLUDE_DIR})
    endif()
  endif()
  set(BOOST_UT_DISABLE_MODULE
    ON
    CACHE BOOL "Disable UT Module Support" FORCE)
  add_compile_definitions(BOOST_UT_DISABLE_MODULE)
endfunction()

function(SetupUtTargetForEmscripten)
  # Boost.UT upstream adds -fwasm-exceptions which conflicts with our -fexceptions (JS exceptions). JS-based exceptions
  # are required for Asyncify compatibility. Remove and replace.
  get_target_property(_ut_copts ut INTERFACE_COMPILE_OPTIONS)
  get_target_property(_ut_lopts ut INTERFACE_LINK_OPTIONS)
  if(_ut_copts)
    list(REMOVE_ITEM _ut_copts -fwasm-exceptions)
    list(APPEND _ut_copts -fexceptions)
    set_target_properties(ut PROPERTIES INTERFACE_COMPILE_OPTIONS "${_ut_copts}")
  endif()
  if(_ut_lopts)
    list(REMOVE_ITEM _ut_lopts -fwasm-exceptions)
    list(APPEND _ut_lopts -fexceptions)
    set_target_properties(ut PROPERTIES INTERFACE_LINK_OPTIONS "${_ut_lopts}")
  endif()
endfunction()


function(ObtainOrFindHttpLib)
  if(FETCH)
    FetchContent_Declare(
      cpp-httplib
      GIT_REPOSITORY https://github.com/yhirose/cpp-httplib.git
      GIT_TAG v0.18.1
      EXCLUDE_FROM_ALL)
    set(GR_FETCH_MAKE_AVAILABLE_DEPS ${GR_FETCH_MAKE_AVAILABLE_DEPS} cpp-httplib PARENT_SCOPE)
  else()
    find_package(httplib CONFIG QUIET)
    if(NOT TARGET httplib::httplib)
      if(NOT PkgConfig_FOUND)
        message(
          FATAL_ERROR "cpp-httplib was not found and pkg-config is unavailable. Install cpp-httplib development files.")
      endif()

      pkg_search_module(
        CPP_HTTPLIB
        QUIET
        IMPORTED_TARGET
        cpp-httplib
        httplib)
      if(NOT CPP_HTTPLIB_FOUND)
        message(FATAL_ERROR "cpp-httplib was not found. Install libcpp-httplib-dev, cpp-httplib-devel, or cpp-httplib.")
      endif()
      add_library(
        httplib::httplib
        INTERFACE
        IMPORTED
        GLOBAL)
      target_link_libraries(httplib::httplib INTERFACE PkgConfig::CPP_HTTPLIB)
    endif()
  endif()
endfunction()
