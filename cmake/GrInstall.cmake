
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
        # Homebrew, where a macOS build gets its LLVM runtime. Bundling these
        # would copy the dylibs in without rewriting any install name, so the
        # binaries would still load the originals from /opt/homebrew and the
        # copies would be dead weight. Excluding them is coherent; making the
        # package self-contained needs an install_name_tool fixup step that does
        # not exist yet, so a macOS package currently expects Homebrew LLVM.
        "^/opt/homebrew"
        "^/usr/local/opt"
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
            # @loader_path, not @executable_path: for an executable the two are
            # identical, but @executable_path resolves against whatever process
            # loaded a .dylib, so a plugin dlopen()ed by a host outside the
            # prefix would look for its siblings next to that host and not find
            # them. @loader_path always resolves against the binary that carries
            # the RPATH.
            #
            # This still only covers artifacts installed under the prefix. A
            # plugin installed into the shared plugin tree needs an absolute
            # RPATH into <install-root>/lib, which nothing sets yet.
            set(INSTALL_RPATH "@loader_path/../lib")
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
