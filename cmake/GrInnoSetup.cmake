#[[
Shared Windows installer configuration for GNU Radio 4.

Every GR project that ships an Inno Setup installer (gr-core, gr-library, ...
and the combined superbuild installer) configures it through this module so
that they all agree on one install layout:

    %LOCALAPPDATA%\Programs\GNURadio4          runtime libraries and headers (user-selectable)
    %LOCALAPPDATA%\.gnuradio-4\plugins\v<api>  plugins
    %LOCALAPPDATA%\.gnuradio-4\manifest\v<api> the manifest describing both roots
    %LOCALAPPDATA%\.gnuradio-4\tools           the manifest maintenance script

The first installer to run lets the user pick the install root and writes the
manifest; every later one reuses the recorded layout, skips the directory page
and only adds its own entries. Reinstalls and upgrades proceed silently,
downgrades ask for confirmation.

Terminology, because the manifest and CPack both use the word "component":

    package   a versioned GR product recorded in the manifest, such as
              gr-core=4.0.0. The manifest keeps packages in two sections,
              "components" and "plugins", which is the split between
              gr_configure_innosetup_installer() and
              gr_configure_innosetup_plugins() below.
    component a CPack / Inno Setup install component, such as CORE or DEVELOP:
              a separately selectable part of one installer. One package
              normally spans several components, so the two are not
              interchangeable and neither implies the other.
#]]

set(GR_INNOSETUP_TEMPLATE_DIR "${CMAKE_CURRENT_LIST_DIR}/../packaging/innosetup")
if(NOT EXISTS "${GR_INNOSETUP_TEMPLATE_DIR}/gr_install_flow.iss.in")
  # installed layout: the templates sit next to this module
  set(GR_INNOSETUP_TEMPLATE_DIR "${CMAKE_CURRENT_LIST_DIR}/packaging/innosetup")
endif()

# Regenerates the installer scripts and CPack wiring from whatever has been
# declared so far. Both public macros call it, so they may be used in any order.
macro(_gr_innosetup_generate)
  if(NOT GR_PLUGIN_API_VERSION)
    message(FATAL_ERROR "gr_configure_innosetup_installer: GR_PLUGIN_API_VERSION is not set")
  endif()

  # the installer script reads these as flat strings
  string(JOIN "|" GR_INSTALLER_COMPONENT_PACKAGES ${GR_INNOSETUP_COMPONENT_PACKAGES})
  string(JOIN "|" GR_INSTALLER_PLUGIN_PACKAGES ${GR_INNOSETUP_PLUGIN_PACKAGES})
  string(JOIN "," GR_INSTALLER_PRESELECTED_COMPONENTS ${GR_INNOSETUP_PRESELECTED_COMPONENTS})

  set(GR_MANIFEST_TOOL "${GR_INNOSETUP_TEMPLATE_DIR}/gr_manifest.ps1")
  set(_GR_INNO_OUTPUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/packaging/innosetup")
  configure_file("${GR_INNOSETUP_TEMPLATE_DIR}/gr_install_flow.iss.in" "${_GR_INNO_OUTPUT_DIR}/gr_install_flow.iss"
                 @ONLY)
  configure_file("${GR_INNOSETUP_TEMPLATE_DIR}/gr_installer_files.iss.in" "${_GR_INNO_OUTPUT_DIR}/gr_installer_files.iss"
                 @ONLY)

  # CPack writes these values into CPackConfig.cmake verbatim; without this the
  # backslashes and braces of the Inno Setup constants below fail to re-parse
  set(CPACK_VERBATIM_VARIABLES ON)

  set(CPACK_INNOSETUP_EXTRA_SCRIPTS "${_GR_INNO_OUTPUT_DIR}/gr_installer_files.iss")
  set(CPACK_INNOSETUP_CODE_FILES "${_GR_INNO_OUTPUT_DIR}/gr_install_flow.iss")

  set(CPACK_INNOSETUP_SETUP_AppId "${GR_INNOSETUP_APP_ID}")
  # the manifest, not Inno's own registry entry, decides where we install
  set(CPACK_INNOSETUP_SETUP_DefaultDirName "{code:GrGetInstallRoot}")
  set(CPACK_INNOSETUP_SETUP_UsePreviousAppDir "no")
  # per-user install, so no UAC prompt and {autopf} resolves to %LOCALAPPDATA%\Programs
  set(CPACK_INNOSETUP_SETUP_PrivilegesRequired "lowest")
  set(CPACK_INNOSETUP_SETUP_AppVersion "${CPACK_PACKAGE_VERSION}")
  set(CPACK_INNOSETUP_SETUP_VersionInfoVersion "${CPACK_PACKAGE_VERSION}")
  set(CPACK_INNOSETUP_SETUP_UninstallDisplayName "${CPACK_PACKAGE_NAME} ${CPACK_PACKAGE_VERSION}")

  foreach(_gr_plugin_component IN LISTS GR_INNOSETUP_PLUGIN_COMPONENTS)
    string(TOUPPER "${_gr_plugin_component}" _gr_plugin_component)
    set(CPACK_INNOSETUP_${_gr_plugin_component}_INSTALL_DIRECTORY "{code:GrGetPluginRoot}")
  endforeach()
endmacro()

#[[
gr_configure_innosetup_installer

Configures the installer itself: its Windows identity, the packages it records
in the manifest's "components" section and the components it pre-selects. Call
it once, before include(CPack), from every GR project that ships a Windows
installer, including plugin-only ones.

Args:
    APP_ID                 Inno Setup AppId; MUST be a GUID that is unique per
                           installer and constant across versions, otherwise
                           Windows treats every release as a separate product
    PACKAGES               "name=version" entries recorded in the manifest's
                           "components" section, one per GR package this
                           installer ships. A superbuild installer lists all of
                           them here
                           (default: "${CPACK_PACKAGE_NAME}=${CPACK_PACKAGE_VERSION}")
    PRESELECTED_COMPONENTS CPack components ticked on a fresh install. CPack
                           pre-selects only components marked REQUIRED, so
                           anything else meant to be on by default belongs here
#]]
macro(gr_configure_innosetup_installer)
  cmake_parse_arguments(GR_INNO "" "APP_ID" "PACKAGES;PRESELECTED_COMPONENTS" ${ARGN})

  if(NOT GR_INNO_APP_ID)
    message(FATAL_ERROR "gr_configure_innosetup_installer: APP_ID is required and must be stable across releases")
  endif()

  set(GR_INNOSETUP_APP_ID "${GR_INNO_APP_ID}")
  set(GR_INNOSETUP_PRESELECTED_COMPONENTS ${GR_INNO_PRESELECTED_COMPONENTS})
  if(GR_INNO_PACKAGES)
    set(GR_INNOSETUP_COMPONENT_PACKAGES ${GR_INNO_PACKAGES})
  else()
    set(GR_INNOSETUP_COMPONENT_PACKAGES "${CPACK_PACKAGE_NAME}=${CPACK_PACKAGE_VERSION}")
  endif()

  _gr_innosetup_generate()
endmacro()

#[[
gr_configure_innosetup_plugins

Adds plugin payload to the installer. Plugins are recorded in the manifest's
"plugins" section rather than its "components" section, and their files go to
the shared plugin tree rather than below the install root, which is why they
are declared separately. May be called before or after
gr_configure_innosetup_installer(); a project that ships no plugins never calls
it at all.

Args:
    PACKAGES   "name=version" entries recorded in the manifest's "plugins"
               section, one per plugin this installer ships
    COMPONENTS CPack components whose files belong in the shared plugin tree.
               Their install() DESTINATION must be "." because CPack appends
               the destination to the component's install directory
#]]
macro(gr_configure_innosetup_plugins)
  cmake_parse_arguments(GR_INNO_PLUGIN "" "" "PACKAGES;COMPONENTS" ${ARGN})

  set(GR_INNOSETUP_PLUGIN_PACKAGES ${GR_INNO_PLUGIN_PACKAGES})
  set(GR_INNOSETUP_PLUGIN_COMPONENTS ${GR_INNO_PLUGIN_COMPONENTS})

  # nothing to generate until the installer identity is known
  if(GR_INNOSETUP_APP_ID)
    _gr_innosetup_generate()
  endif()
endmacro()
