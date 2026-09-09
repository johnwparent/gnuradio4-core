

macro(CheckPythonAvailability)
    # check for CPython and Numpy dependencies
    set(PYTHON_FORCE_INCLUDE OFF)
    if(PYTHON_FORCE_INCLUDE)
    find_package(Python3 3.12 REQUIRED COMPONENTS Interpreter Development NumPy)
    else()
    find_package(Python3 3.12 COMPONENTS Interpreter Development NumPy)
    endif()

    set(PYTHON_AVAILABLE OFF)
    if(Python3_FOUND AND NOT EMSCRIPTEN)
    execute_process(
        COMMAND ${Python3_EXECUTABLE} "${CMAKE_CURRENT_SOURCE_DIR}/cmake/CheckNumPy.py"
        RESULT_VARIABLE NUMPY_NOT_FOUND
        OUTPUT_VARIABLE NUMPY_INCLUDE_DIR
        OUTPUT_STRIP_TRAILING_WHITESPACE)

    # If NumPy is found, set PYTHON_AVAILABLE to ON
    if(NOT NUMPY_NOT_FOUND)
        set(PYTHON_AVAILABLE ON)
        message(STATUS "Using Python Include Dirs: ${Python3_INCLUDE_DIRS} and ${NUMPY_INCLUDE_DIR}")
    else()
        message(STATUS "Python and Numpy Include headers not found!!")
    endif()
    endif()
endmacro()


macro(SetupMagicEnumTarget)
    # include header-only libraries that have been inlined to simplify builds w/o requiring access to the internet
    add_library(magic_enum INTERFACE)
    add_library(gnuradio4::magic_enum ALIAS magic_enum)
    target_include_directories(
        magic_enum ${CMAKE_EXT_DEP_WARNING_GUARD} INTERFACE $<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/third_party/magic_enum/>
                                                            $<INSTALL_INTERFACE:include>)

    set(magic_enum_public_headers third_party/magic_enum/magic_enum.hpp third_party/magic_enum/magic_enum_utility.hpp)
    set_target_properties(magic_enum PROPERTIES PUBLIC_HEADER "${magic_enum_public_headers}")
endmacro()


macro(SetupCoverageSupport)
    message("Coverage reporting enabled")
    include(cmake/CodeCoverage.cmake) # https://github.com/bilke/cmake-modules/blob/master/CodeCoverage.cmake #
    # (License: BSL-1.0)
    target_compile_options(
        gnuradio-options
        INTERFACE --coverage
                -Og
                -g1
                -gz
        # -gdwarf-2 -gstrict-dwarf -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0
    ) # fortify_source is not possible without optimization
    target_link_libraries(gnuradio-options INTERFACE --coverage)
    append_coverage_compiler_flags()
    set(GCOVR_ADDITIONAL_ARGS "--merge-mode-functions=merge-use-line-min"
                                "--gcov-ignore-parse-errors=negative_hits.warn_once_per_file")
    set(GR4_CORE_COVERAGE_DEPENDENCIES
        qa_buffer
        qa_AtomicBitset
        qa_AtomicRef
        qa_Value
        qa_ValueHelper
        qa_ComputeDomain
        qa_DataSet
        qa_DynamicPort
        qa_LifeCycle
        qa_MemoryAllocators
        qa_PmtCollections
        qa_Port
        qa_Profiler
        qa_Tensor
        qa_TensorMath
        qa_SVD
        qa_TriggerMatcher
        qa_YamlPmt
        qa_PortableTypeName
        qa_thread_affinity
        qa_thread_pool
        qa_SubGraphAssets
        qa_fixed_string
        qa_reflection
        qa_formatter
        qa_traits
        qa_type_name
        qa_UncertainValue
        qa_RangesHelper)
    setup_target_for_coverage_gcovr_xml(
        NAME
        coverage
        EXECUTABLE
        ctest
        EXECUTABLE_ARGS
        "--output-on-failure"
        DEPENDENCIES
        ${GR4_CORE_COVERAGE_DEPENDENCIES}
        EXCLUDE
        "${CMAKE_BINARY_DIR}/*")
    setup_target_for_coverage_gcovr_html(
        NAME
        coverage_html
        EXECUTABLE
        ctest
        EXECUTABLE_ARGS
        "--output-on-failure"
        DEPENDENCIES
        ${GR4_CORE_COVERAGE_DEPENDENCIES}
        EXCLUDE
        "${CMAKE_BINARY_DIR}/*")
endmacro()


function(SetupEmscriptenGnuRadioOptions)
  # Make sure consumers of gnuradio4::gnuradio-options don't accidentally build with conflicting arguments
  target_compile_definitions(gnuradio-options INTERFACE GR_MAX_WASM_THREAD_COUNT=${GR_MAX_WASM_THREAD_COUNT})
  target_compile_options(gnuradio-options INTERFACE -fexceptions -pthread)
  target_link_options(
    gnuradio-options
    INTERFACE
    "SHELL:-s ALLOW_MEMORY_GROWTH=1"
    "SHELL:-s ASSERTIONS=1"
    "SHELL:-s INITIAL_MEMORY=256MB"
    "SHELL:-s STACK_SIZE=4194304"
    # "SHELL:-s SAFE_HEAP=1" # additional for debug "SHELL:-s ASSERTIONS=2" # additional for debug "SHELL:-s
    # STACK_OVERFLOW_CHECK=2" # additional for debug "SHELL:-g" # additional for debug "SHELL:-gsource-map" # additional
    # for debug "SHELL:--profiling-funcs" # additional for debug "SHELL:--emit-symbol-map" # additional for debug
    -fexceptions
    -pthread
    "SHELL:-s PTHREAD_POOL_SIZE=${GR_MAX_WASM_THREAD_COUNT}"
    "SHELL:-s PTHREAD_POOL_SIZE_STRICT=2"
    "SHELL:-s FETCH=1"
    "SHELL:-s WASM=1" # output as web-assembly
    "SHELL:-s EXPORTED_RUNTIME_METHODS=['ccall']"
    "SHELL:-s ENVIRONMENT=web,worker,node")
    set(CMAKE_EXECUTABLE_SUFFIX ".js" PARENT_SCOPE)
endfunction()


function(ReportConfigurationState)
    # print effective options
    message(STATUS "================================================")
    message(STATUS "GR-4 build configuration")
    message(STATUS "------------------------------------------------")
    message(STATUS "GR_TOPLEVEL_PROJECT          : ${GR_TOPLEVEL_PROJECT}")
    message(STATUS "GR_ENABLE_BLOCK_REGISTRY     : ${GR_ENABLE_BLOCK_REGISTRY}")
    message(STATUS "INTERNAL_ENABLE_BLOCK_PLUGINS: ${INTERNAL_ENABLE_BLOCK_PLUGINS}")
    message(STATUS "USE_CCACHE                   : ${USE_CCACHE}")
    message(STATUS "WARNINGS_AS_ERRORS           : ${WARNINGS_AS_ERRORS}")
    message(STATUS "TIMETRACE                    : ${TIMETRACE}")
    message(STATUS "ADDRESS_SANITIZER            : ${ADDRESS_SANITIZER}")
    message(STATUS "UB_SANITIZER                 : ${UB_SANITIZER}")
    message(STATUS "THREAD_SANITIZER             : ${THREAD_SANITIZER}")
    message(STATUS "ENABLE_TBB                   : ${ENABLE_TBB}")
    message(STATUS "ENABLE_EXAMPLES              : ${ENABLE_EXAMPLES}")
    message(STATUS "ENABLE_TESTING               : ${ENABLE_TESTING}")
    message(STATUS "GR_PACKAGING                 : ${GR_PACKAGING}")
    message(STATUS "ENABLE_COVERAGE              : ${ENABLE_COVERAGE}")
    message(STATUS "GR_MAX_WASM_THREAD_COUNT     : ${GR_MAX_WASM_THREAD_COUNT}")
    message(STATUS "------------------------------------------------")

    string(TOUPPER "${CMAKE_BUILD_TYPE}" _BT)
    set(_config_cxx_flags "${CMAKE_CXX_FLAGS_${_BT}}")
    set(_config_link_flags "${CMAKE_EXE_LINKER_FLAGS_${_BT}}")
    set(_base_cxx_flags "${CMAKE_CXX_FLAGS}")
    set(_base_link_flags "${CMAKE_EXE_LINKER_FLAGS}")
    get_directory_property(_dir_compile_opts COMPILE_OPTIONS)
    get_directory_property(_dir_link_opts LINK_OPTIONS)
    get_target_property(_t_copts gnuradio-options INTERFACE_COMPILE_OPTIONS)
    get_target_property(_t_lopts gnuradio-options INTERFACE_LINK_OPTIONS)
    if(_t_lopts STREQUAL "_t_lopts-NOTFOUND")
    unset(_t_lopts)
    endif()

    string(
    JOIN
    " "
    _final_compile_opts
    ${_base_cxx_flags}
    ${_config_cxx_flags}
    ${_dir_compile_opts}
    ${_t_copts})
    string(
    JOIN
    " "
    _final_link_opts
    ${_base_link_flags}
    ${_config_link_flags}
    ${_dir_link_opts}
    ${_t_lopts})

    message(STATUS "Effective compiler flags : ${_final_compile_opts}")
    message(STATUS "Effective linker flags   : ${_final_link_opts}")
    message(STATUS "------------------------------------------------")
    message(STATUS "Toolchain details")
    message(STATUS "------------------------------------------------")
    message(STATUS "C++ compiler ID          : ${CMAKE_CXX_COMPILER_ID}")
    message(STATUS "GR_USE_ADAPTIVE_CPP?     : ${GR_USE_ADAPTIVE_CPP}")
    message(STATUS "C++ compiler path        : ${CMAKE_CXX_COMPILER}")
    message(STATUS "C++ compiler version     : ${CMAKE_CXX_COMPILER_VERSION}")
    string(
    REGEX MATCH
            "-fuse-ld=([a-zA-Z0-9._-]+)"
            _linker_backend
            "${_final_link_opts}")
    if(_linker_backend MATCHES "-fuse-ld=([a-zA-Z0-9._-]+)")
    set(_detected_linker "${CMAKE_CXX_COMPILER} with ${CMAKE_MATCH_1}")
    else()
    set(_detected_linker "${CMAKE_LINKER} (default/provided linker)")
    endif()
    message(STATUS "Linker                   : ${_detected_linker}")

    if(CCACHE_PROGRAM)
    execute_process(
        COMMAND ${CCACHE_PROGRAM} --version
        OUTPUT_VARIABLE CCACHE_VERSION
        OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
    string(
        REGEX MATCH
            "[^\n]*"
            CCACHE_VERSION_LINE
            "${CCACHE_VERSION}")
    message(STATUS "ccache                   : ${CCACHE_VERSION_LINE}")
    else()
    message(STATUS "ccache                   : not found or disabled")
    endif()

    message(STATUS "================================================")

endfunction()

# Regexes that keep system libraries out of the packages. The Windows API sets
# resolve to no file at all and have to be dropped before resolution is tried.
function(_gr_runtime_dependency_excludes OUT_VAR)
    set(${OUT_VAR}
        PRE_EXCLUDE_REGEXES
        "api-ms-win-.*"
        "ext-ms-.*"
        "^/lib"
        "^/usr/lib"
        "^/usr/local/lib"
        "^/System/Library"
        "^/usr/lib/libSystem"
        "^[Cc]:[\\/][Ww][Ii][Nn][Dd][Oo][Ww][Ss]"
        POST_EXCLUDE_REGEXES
        ".*[Ss][Yy][Ss][Tt][Ee][Mm]32.*"
        ".*[Ww][Ii][Nn][Ss][Xx][Ss].*"
        PARENT_SCOPE)
endfunction()

# Gives every forwarded FILE_SET / PUBLIC_HEADER / PRIVATE_HEADER group its own
# COMPONENT. It cannot be left to the caller: an exported target must install
# its file sets in the same install() command, and this function consumes the
# COMPONENT keyword, so without this the headers would fall into "Unspecified".
function(_gr_apply_headers_component OUT_VAR COMPONENT_NAME)
    set(RESULT)
    set(NEXT_IS_FILE_SET_NAME FALSE)
    foreach(ARG IN LISTS ARGN)
        list(APPEND RESULT "${ARG}")
        if(NEXT_IS_FILE_SET_NAME)
            set(NEXT_IS_FILE_SET_NAME FALSE)
            list(APPEND RESULT COMPONENT "${COMPONENT_NAME}")
        elseif(ARG STREQUAL "FILE_SET")
            set(NEXT_IS_FILE_SET_NAME TRUE)
        elseif(ARG MATCHES "^(PUBLIC_HEADER|PRIVATE_HEADER)$")
            list(APPEND RESULT COMPONENT "${COMPONENT_NAME}")
        endif()
    endforeach()
    set(${OUT_VAR} "${RESULT}" PARENT_SCOPE)
endfunction()

#[[
gr_install_artifact
The install entry point for everything GR puts on disc. Takes any install()
signature and adds what the GR installers rely on, so no project has to
remember a follow-up call.

Args:
    COMPONENT         - the install component to associate the artifact with,
                        default is "CORE"
    HEADERS_COMPONENT - the install component for FILE_SET, PUBLIC_HEADER and
                        PRIVATE_HEADER groups, default is COMPONENT. Use it to
                        put an exported library's binaries and its headers in
                        different components, which has to happen in one call
                        because CMake requires an exported target to install its
                        file sets alongside the export
    ARCHIVE_COMPONENT - the install component for static libraries and, on
                        Windows, import libraries, default is COMPONENT. Both
                        are only needed to build against GR, so they usually
                        belong with the headers rather than with the runtime

Every other argument is forwarded to install() exactly as provided by the
caller, so TARGETS, FILES, PROGRAMS, DIRECTORY, EXPORT, SCRIPT and FILE_SET all
behave as usual.

For TARGETS the runtime, library and archive destinations are supplied here so
that all GR artifacts share one layout: on Windows the DLLs sit next to the
executables, elsewhere they go to lib/ and the binaries get an RPATH that finds
them. Executables, shared libraries and module libraries additionally pull in
the third-party libraries they load at runtime. Those are resolved by this same
install() command, which is what guarantees they land in the same destination
and component as the artifact needing them. Everything else - static, object and
interface libraries, files, directories, exports - has no runtime dependencies
and skips that step.
#]]
function(gr_install_artifact)
    cmake_parse_arguments("GR_INSTALL" "" "COMPONENT;HEADERS_COMPONENT;ARCHIVE_COMPONENT;EXPORT" "TARGETS;DIRECTORY"
                          ${ARGN})
    if(NOT GR_INSTALL_COMPONENT)
        set(GR_INSTALL_COMPONENT "CORE")
    endif()
    if(NOT GR_INSTALL_HEADERS_COMPONENT)
        set(GR_INSTALL_HEADERS_COMPONENT "${GR_INSTALL_COMPONENT}")
    endif()
    if(NOT GR_INSTALL_ARCHIVE_COMPONENT)
        set(GR_INSTALL_ARCHIVE_COMPONENT "${GR_INSTALL_COMPONENT}")
    endif()
    if(POLICY CMP0207)
        # match the runtime dependency exclude regexes against normalised paths
        cmake_policy(SET CMP0207 NEW)
    endif()

    if(GR_INSTALL_DIRECTORY)
        # COMPONENT has to precede any FILES_MATCHING/PATTERN rules; appended, it is a hard error
        install(DIRECTORY ${GR_INSTALL_DIRECTORY} COMPONENT ${GR_INSTALL_COMPONENT}
                ${GR_INSTALL_UNPARSED_ARGUMENTS})
        return()
    endif()

    set(EXPORT_ARGS)
    if(GR_INSTALL_EXPORT)
        set(EXPORT_ARGS EXPORT ${GR_INSTALL_EXPORT})
    endif()

    if(NOT GR_INSTALL_TARGETS)
        # FILES, PROGRAMS, EXPORT, SCRIPT/CODE: no artifact kinds to place
        install(${EXPORT_ARGS} ${GR_INSTALL_UNPARSED_ARGUMENTS} COMPONENT ${GR_INSTALL_COMPONENT})
        return()
    endif()

    if(WIN32)
        set(BIN_DEST "bin")
        set(LIB_DEST "bin")
    else()
        set(BIN_DEST "bin")
        set(LIB_DEST "lib")
        if(APPLE)
            set(INSTALL_RPATH "@executable_path/../lib")
        else()
            set(INSTALL_RPATH "$ORIGIN/../lib")
        endif()
    endif()

    # only loadable artifacts have runtime dependencies or an RPATH to speak of
    set(RUNTIME_DEPENDENCY_ARGS)
    foreach(TARGET_NAME IN LISTS GR_INSTALL_TARGETS)
        get_target_property(TARGET_TYPE ${TARGET_NAME} TYPE)
        if(NOT TARGET_TYPE MATCHES "^(EXECUTABLE|SHARED_LIBRARY|MODULE_LIBRARY)$")
            continue()
        endif()
        # the RPATH is what makes any install runnable, packaged or not
        if(NOT WIN32)
            set_target_properties(${TARGET_NAME} PROPERTIES INSTALL_RPATH "${INSTALL_RPATH}")
        endif()
        # bundling third-party libraries is only wanted when building a package
        if(GR_PACKAGING)
            _gr_runtime_dependency_excludes(RUNTIME_DEPENDENCY_EXCLUDES)
            set(RUNTIME_DEPENDENCY_ARGS RUNTIME_DEPENDENCIES ${RUNTIME_DEPENDENCY_EXCLUDES})
        endif()
    endforeach()

    _gr_apply_headers_component(FORWARDED_ARGS "${GR_INSTALL_HEADERS_COMPONENT}" ${GR_INSTALL_UNPARSED_ARGUMENTS})
    install(
        TARGETS ${GR_INSTALL_TARGETS} ${EXPORT_ARGS} ${RUNTIME_DEPENDENCY_ARGS} ${FORWARDED_ARGS}
        RUNTIME DESTINATION ${BIN_DEST} COMPONENT ${GR_INSTALL_COMPONENT}
        LIBRARY DESTINATION ${LIB_DEST} COMPONENT ${GR_INSTALL_COMPONENT}
        ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR} COMPONENT ${GR_INSTALL_ARCHIVE_COMPONENT})
endfunction()
