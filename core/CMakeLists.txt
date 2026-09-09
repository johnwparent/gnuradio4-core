add_library(
  gnuradio-core STATIC
  src/Value.cpp
  src/ValueHelper.cpp
  src/Block.cpp
  src/BlockModel.cpp
  src/Settings.cpp
  src/Graph.cpp
  src/PluginLoader.cpp
  src/PmtTypeHelpers.cpp)


target_sources(gnuradio-core
PUBLIC
FILE_SET core_headers
TYPE HEADERS
BASE_DIRS ${CMAKE_CURRENT_LIST_DIR}
FILES
  include/gnuradio-4.0/annotated.hpp
  include/gnuradio-4.0/AtomicBitset.hpp
  include/gnuradio-4.0/Block.hpp
  include/gnuradio-4.0/BlockMerging.hpp
  include/gnuradio-4.0/BlockModel.hpp
  include/gnuradio-4.0/BlockTraits.hpp
  include/gnuradio-4.0/Buffer.hpp
  include/gnuradio-4.0/BufferSkeleton.hpp
  include/gnuradio-4.0/CircularBuffer.hpp
  include/gnuradio-4.0/ClaimStrategy.hpp
  include/gnuradio-4.0/BlockingSync.hpp
  include/gnuradio-4.0/DataSet.hpp
  include/gnuradio-4.0/Graph_yaml_importer.hpp
  include/gnuradio-4.0/Graph.hpp
  include/gnuradio-4.0/HistoryBuffer.hpp
  include/gnuradio-4.0/LifeCycle.hpp
  include/gnuradio-4.0/MemoryAllocators.hpp
  include/gnuradio-4.0/Message.hpp
  include/gnuradio-4.0/PluginLoader.hpp
  include/gnuradio-4.0/PmtCollections.hpp
  include/gnuradio-4.0/Port.hpp
  include/gnuradio-4.0/PortTraits.hpp
  include/gnuradio-4.0/Profiler.hpp
  include/gnuradio-4.0/reader_writer_lock.hpp
  include/gnuradio-4.0/Scheduler.hpp
  include/gnuradio-4.0/Sequence.hpp
  include/gnuradio-4.0/Settings.hpp
  include/gnuradio-4.0/Tag.hpp
  include/gnuradio-4.0/Tensor.hpp
  include/gnuradio-4.0/TensorMath.hpp
  include/gnuradio-4.0/TriggerMatcher.hpp
  include/gnuradio-4.0/Value.hpp
  include/gnuradio-4.0/ValueHelper.hpp
  include/gnuradio-4.0/formatter/ValueFormatter.hpp
  include/gnuradio-4.0/formatter/ValueHelperFormatter.hpp
  include/gnuradio-4.0/WaitStrategy.hpp
  include/gnuradio-4.0/YamlPmt.hpp
)


add_library(gnuradio4::gnuradio-core ALIAS gnuradio-core)
target_include_directories(
  gnuradio-core
  PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include/>
         $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/src>
         $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/include>
         $<INSTALL_INTERFACE:include/>)

target_link_libraries(
  gnuradio-core
  PUBLIC gnuradio-options
         gnuradio-meta
         magic_enum
         vir)

if(EMSCRIPTEN)
  add_library(gnuradio-blocklib-core STATIC src/BlockRegistry.cpp)
else()
  add_library(gnuradio-blocklib-core SHARED src/BlockRegistry.cpp)
endif()
set(blocklib_public_headers include/gnuradio-4.0/BlockRegistry.hpp include/gnuradio-4.0/Plugin.hpp)
set_target_properties(gnuradio-blocklib-core PROPERTIES PUBLIC_HEADER "${blocklib_public_headers}")
add_library(gnuradio4::gnuradio-blocklib-core ALIAS gnuradio-blocklib-core)
message(INFO "PATH include " $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/>)
target_include_directories(gnuradio-blocklib-core PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/>
                                                         $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>)
target_link_libraries(gnuradio-blocklib-core PUBLIC gnuradio-core)
if(WIN32)
  target_compile_definitions(gnuradio-core PUBLIC BUILDING_MYPLUGIN)
endif()

# configure a header file to pass the CMake settings to the source code
configure_file("${PROJECT_SOURCE_DIR}/cmake/config.hpp.in"
               "${CMAKE_CURRENT_BINARY_DIR}/include/gnuradio-4.0/config.hpp" @ONLY)
# TODO: install configure file... but not really meaningful for header only library, since compile flags are defined by
# the user...
gr_install_artifact(FILES "${CMAKE_CURRENT_BINARY_DIR}/include/gnuradio-4.0/config.hpp"
        DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}/gnuradio-4.0" COMPONENT DEVELOP)

gr_install_artifact(
  TARGETS gnuradio-core gnuradio-blocklib-core
  EXPORT gnuradio4Targets
  FILE_SET core_headers DESTINATION include/gnuradio-4.0)

# Just install the entire include directory
# Todo: this is redundant with the above fileset install/export, ensure we need both, and if so maybe drop the install and keep the export for the fileset (or include these)
gr_install_artifact(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/include/ DESTINATION ${CMAKE_INSTALL_INCLUDEDIR} COMPONENT DEVELOP)

add_subdirectory(src)

if(ENABLE_TESTING)
  add_subdirectory(test)
endif()

if(ENABLE_BENCH)
  add_subdirectory(benchmarks)
endif()
